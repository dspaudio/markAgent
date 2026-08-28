import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt
import Observation

@MainActor
@Observable
final class SystemStatusModel {
    typealias AssertionID = IOPMAssertionID

    struct Operations: Sendable {
        let createAssertion: @Sendable () throws -> AssertionID
        let releaseAssertion: @Sendable (AssertionID) throws -> Void
        let sampleResidentMemory: @Sendable () throws -> UInt64

        static let live = Operations(
            createAssertion: {
                var assertionID = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "MarkAgent Caffeinate" as CFString,
                    &assertionID
                )
                guard result == kIOReturnSuccess else {
                    throw SystemStatusError.assertionCreateFailed(result)
                }
                return assertionID
            },
            releaseAssertion: { assertionID in
                let result = IOPMAssertionRelease(assertionID)
                guard result == kIOReturnSuccess else {
                    throw SystemStatusError.assertionReleaseFailed(result)
                }
            },
            sampleResidentMemory: {
                var info = mach_task_basic_info()
                var count = mach_msg_type_number_t(
                    MemoryLayout<mach_task_basic_info_data_t>.size
                        / MemoryLayout<natural_t>.size
                )
                let result = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(
                        to: integer_t.self,
                        capacity: Int(count)
                    ) { reboundPointer in
                        task_info(
                            mach_task_self_,
                            task_flavor_t(MACH_TASK_BASIC_INFO),
                            reboundPointer,
                            &count
                        )
                    }
                }
                guard result == KERN_SUCCESS else {
                    throw SystemStatusError.memorySampleFailed(result)
                }
                return UInt64(info.resident_size)
            }
        )
    }

    private(set) var isCaffeinateEnabled = false
    private(set) var residentMemoryBytes: UInt64?
    private(set) var errorMessage: String?

    private let operations: Operations
    private var assertionID: AssertionID?
    private var desiredCaffeinateEnabled = false
    private var caffeinateTransitionTask: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?

    init(operations: Operations = .live) {
        self.operations = operations
    }

    func setCaffeinateEnabled(_ isEnabled: Bool) async {
        desiredCaffeinateEnabled = isEnabled
        if caffeinateTransitionTask == nil {
            caffeinateTransitionTask = Task { [weak self] in
                await self?.reconcileCaffeinateState()
            }
        }
        await caffeinateTransitionTask?.value
    }

    private func reconcileCaffeinateState() async {
        defer { caffeinateTransitionTask = nil }

        while desiredCaffeinateEnabled != isCaffeinateEnabled {
            if desiredCaffeinateEnabled {
                guard assertionID == nil else {
                    isCaffeinateEnabled = true
                    continue
                }
                let createAssertion = operations.createAssertion
                do {
                    let newAssertionID = try await Task.detached(priority: .userInitiated) {
                        try createAssertion()
                    }.value
                    assertionID = newAssertionID
                    isCaffeinateEnabled = true
                    errorMessage = nil
                } catch {
                    errorMessage = String(localized: "Caffeinate를 활성화할 수 없습니다.")
                    break
                }
            } else {
                guard let assertionID else {
                    isCaffeinateEnabled = false
                    continue
                }
                do {
                    try await release(assertionID)
                    self.assertionID = nil
                    isCaffeinateEnabled = false
                    errorMessage = nil
                } catch {
                    errorMessage = String(localized: "Caffeinate를 비활성화할 수 없습니다.")
                    break
                }
            }
        }
    }

    private func release(_ assertionID: AssertionID) async throws {
        let releaseAssertion = operations.releaseAssertion
        try await Task.detached(priority: .userInitiated) {
            try releaseAssertion(assertionID)
        }.value
    }

    func sampleResidentMemory() async {
        let sampleResidentMemory = operations.sampleResidentMemory
        do {
            residentMemoryBytes = try await Task.detached(priority: .utility) {
                try sampleResidentMemory()
            }.value
            errorMessage = nil
        } catch {
            residentMemoryBytes = nil
            errorMessage = String(localized: "메모리 사용량을 읽을 수 없습니다.")
        }
    }

    func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            await self?.sampleResidentMemory()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await self?.sampleResidentMemory()
            }
        }
    }

    func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    func stop() async {
        stopSampling()
        await setCaffeinateEnabled(false)
    }

}

private enum SystemStatusError: Error {
    case assertionCreateFailed(IOReturn)
    case assertionReleaseFailed(IOReturn)
    case memorySampleFailed(kern_return_t)
}
