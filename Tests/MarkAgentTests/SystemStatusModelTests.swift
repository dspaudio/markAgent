import Foundation
import XCTest
@testable import ma

final class SystemStatusModelTests: XCTestCase {
    @MainActor
    func testEnablingTwiceCreatesOnlyOneAssertionAndDisablingReleasesIt() async {
        let recorder = OperationRecorder(assertionID: 42)
        let model = SystemStatusModel(operations: recorder.operations)

        await model.setCaffeinateEnabled(true)
        await model.setCaffeinateEnabled(true)

        XCTAssertTrue(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.createCount, 1)

        await model.setCaffeinateEnabled(false)

        XCTAssertFalse(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.releasedAssertionIDs, [42])
    }

    @MainActor
    func testStopReleasesAnActiveAssertionOnlyOnce() async {
        let recorder = OperationRecorder(assertionID: 7)
        let model = SystemStatusModel(operations: recorder.operations)

        await model.setCaffeinateEnabled(true)
        await model.stop()
        await model.stop()

        XCTAssertFalse(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.releasedAssertionIDs, [7])
    }

    @MainActor
    func testMemorySampleUpdatesResidentBytesOffTheMainThread() async {
        let recorder = OperationRecorder(assertionID: 1, residentMemoryBytes: 123_456)
        let model = SystemStatusModel(operations: recorder.operations)

        await model.sampleResidentMemory()

        XCTAssertEqual(model.residentMemoryBytes, 123_456)
        XCTAssertEqual(recorder.memorySampleCount, 1)
        XCTAssertEqual(recorder.operationRanOnMainThread, [false])
    }

    @MainActor
    func testAssertionOperationsRunOffTheMainThread() async {
        let recorder = OperationRecorder(assertionID: 9)
        let model = SystemStatusModel(operations: recorder.operations)

        await model.setCaffeinateEnabled(true)
        await model.stop()

        XCTAssertEqual(recorder.operationRanOnMainThread, [false, false])
    }

    @MainActor
    func testRapidEnableThenDisableCreatesOneAssertionAndReleasesIt() async {
        let creationStarted = expectation(description: "assertion creation started")
        let recorder = BlockingOperationRecorder(
            assertionID: 99,
            creationStarted: creationStarted
        )
        let model = SystemStatusModel(operations: recorder.operations)

        let enable = Task { await model.setCaffeinateEnabled(true) }
        await fulfillment(of: [creationStarted], timeout: 1)
        let repeatedEnable = Task { await model.setCaffeinateEnabled(true) }
        let disable = Task { await model.setCaffeinateEnabled(false) }
        recorder.finishCreation()

        await enable.value
        await repeatedEnable.value
        await disable.value

        XCTAssertFalse(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.createCount, 1)
        XCTAssertEqual(recorder.releasedAssertionIDs, [99])
    }

    @MainActor
    func testReleaseFailureKeepsAssertionOwnedAndAllowsRetry() async {
        let recorder = FailingReleaseRecorder(assertionID: 77)
        let model = SystemStatusModel(operations: recorder.operations)

        await model.setCaffeinateEnabled(true)
        await model.setCaffeinateEnabled(false)

        XCTAssertTrue(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.releaseCount, 1)

        await model.setCaffeinateEnabled(false)

        XCTAssertTrue(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.releaseCount, 2)
    }

    @MainActor
    func testRapidDisableReleaseFailurePreservesCreatedAssertionForRetry() async {
        let creationStarted = expectation(description: "assertion creation started")
        let recorder = BlockingOperationRecorder(
            assertionID: 101,
            creationStarted: creationStarted,
            shouldFailRelease: true
        )
        let model = SystemStatusModel(operations: recorder.operations)

        let enable = Task { await model.setCaffeinateEnabled(true) }
        await fulfillment(of: [creationStarted], timeout: 1)
        let disable = Task { await model.setCaffeinateEnabled(false) }
        recorder.finishCreation()

        await enable.value
        await disable.value

        XCTAssertTrue(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.createCount, 1)
        XCTAssertEqual(recorder.releasedAssertionIDs, [101])

        await model.setCaffeinateEnabled(false)

        XCTAssertTrue(model.isCaffeinateEnabled)
        XCTAssertEqual(recorder.releasedAssertionIDs, [101, 101])
    }
}

private final class OperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let assertionID: SystemStatusModel.AssertionID
    private let sampledBytes: UInt64
    private var creates = 0
    private var releases: [SystemStatusModel.AssertionID] = []
    private var samples = 0
    private var mainThreadFlags: [Bool] = []

    init(assertionID: SystemStatusModel.AssertionID, residentMemoryBytes: UInt64 = 0) {
        self.assertionID = assertionID
        self.sampledBytes = residentMemoryBytes
    }

    var operations: SystemStatusModel.Operations {
        SystemStatusModel.Operations(
            createAssertion: { [self] in
                lock.withLock {
                    creates += 1
                    mainThreadFlags.append(Thread.isMainThread)
                }
                return assertionID
            },
            releaseAssertion: { [self] assertionID in
                lock.withLock {
                    releases.append(assertionID)
                    mainThreadFlags.append(Thread.isMainThread)
                }
            },
            sampleResidentMemory: { [self] in
                lock.withLock {
                    samples += 1
                    mainThreadFlags.append(Thread.isMainThread)
                }
                return sampledBytes
            }
        )
    }

    var createCount: Int { lock.withLock { creates } }
    var releasedAssertionIDs: [SystemStatusModel.AssertionID] { lock.withLock { releases } }
    var memorySampleCount: Int { lock.withLock { samples } }
    var operationRanOnMainThread: [Bool] { lock.withLock { mainThreadFlags } }
}

private final class BlockingOperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let condition = NSCondition()
    private let assertionID: SystemStatusModel.AssertionID
    private let creationStarted: XCTestExpectation
    private let shouldFailRelease: Bool
    private var mayFinishCreation = false
    private var creates = 0
    private var releases: [SystemStatusModel.AssertionID] = []

    init(
        assertionID: SystemStatusModel.AssertionID,
        creationStarted: XCTestExpectation,
        shouldFailRelease: Bool = false
    ) {
        self.assertionID = assertionID
        self.creationStarted = creationStarted
        self.shouldFailRelease = shouldFailRelease
    }

    var operations: SystemStatusModel.Operations {
        .init(
            createAssertion: { [self] in
                lock.withLock { creates += 1 }
                creationStarted.fulfill()
                condition.lock()
                while !mayFinishCreation {
                    condition.wait()
                }
                condition.unlock()
                return assertionID
            },
            releaseAssertion: { [self] assertionID in
                lock.withLock { releases.append(assertionID) }
                if shouldFailRelease {
                    throw TestReleaseFailure.failed
                }
            },
            sampleResidentMemory: { 0 }
        )
    }

    func finishCreation() {
        condition.lock()
        mayFinishCreation = true
        condition.broadcast()
        condition.unlock()
    }

    var createCount: Int { lock.withLock { creates } }
    var releasedAssertionIDs: [SystemStatusModel.AssertionID] { lock.withLock { releases } }
}

private final class FailingReleaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let assertionID: SystemStatusModel.AssertionID
    private var releases = 0

    init(assertionID: SystemStatusModel.AssertionID) {
        self.assertionID = assertionID
    }

    var operations: SystemStatusModel.Operations {
        .init(
            createAssertion: { [assertionID] in assertionID },
            releaseAssertion: { [self] _ in
                lock.withLock { releases += 1 }
                throw TestReleaseFailure.failed
            },
            sampleResidentMemory: { 0 }
        )
    }

    var releaseCount: Int { lock.withLock { releases } }
}

private enum TestReleaseFailure: Error {
    case failed
}
