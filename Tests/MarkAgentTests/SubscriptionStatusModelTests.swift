import Foundation
import XCTest
@testable import ma

@MainActor
final class SubscriptionStatusModelTests: XCTestCase {
    func testProvidersDefaultToDisabledUntilExplicitlyRegistered() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = SubscriptionStatusModel(defaults: defaults, loaders: [:])

        XCTAssertEqual(SubscriptionProvider.allCases, [.claude, .codex])
        XCTAssertTrue(model.enabledProviders.isEmpty)
        XCTAssertEqual(model.state(for: .claude), .disabled)
        XCTAssertEqual(model.state(for: .codex), .disabled)
    }

    func testEnabledProvidersPersistAndDisabledProviderDoesNotLoad() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calls = CallCounter()
        let model = SubscriptionStatusModel(defaults: defaults, loaders: [.claude: {
            await calls.increment()
            return SubscriptionUsage(primary: Self.window(percent: 10))
        }])

        model.setEnabled(true, for: .codex)
        model.setEnabled(false, for: .claude)
        await model.refresh(.claude)

        XCTAssertEqual(model.state(for: .claude), .disabled)
        let callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(defaults.stringArray(forKey: SubscriptionStatusModel.enabledProvidersDefaultsKey), ["codex"])

        let restored = SubscriptionStatusModel(defaults: defaults, loaders: [:])
        XCTAssertEqual(restored.enabledProviders, [.codex])
        XCTAssertEqual(restored.state(for: .claude), .disabled)
    }

    func testRefreshPublishesLoadingThenOneOrTwoUsageWindows() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let started = expectation(description: "loader started")
        let loader = ControlledUsageLoader(started: [started])
        let model = SubscriptionStatusModel(defaults: defaults, loaders: [.claude: { try await loader.load() }])
        model.setEnabled(true, for: .claude)
        let refresh = Task { @MainActor in await model.refresh(.claude) }

        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(model.state(for: .claude), .loading)

        let primary = Self.window(name: "Five hour", percent: 37.5)
        let secondary = Self.window(name: "Seven day", percent: 81, resetOffset: 7_200)
        await loader.complete(call: 0, with: .success(SubscriptionUsage(primary: primary, secondary: secondary)))
        _ = await refresh.value

        XCTAssertEqual(model.state(for: .claude), .available(SubscriptionUsage(primary: primary, secondary: secondary)))
        XCTAssertEqual(SubscriptionUsage(primary: primary).windows, [primary])
        XCTAssertEqual(SubscriptionUsage(primary: primary, secondary: secondary).windows, [primary, secondary])
    }

    func testSequentialRefreshPublishesNewestCompletion() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstStarted = expectation(description: "first loader started")
        let secondStarted = expectation(description: "second loader started")
        let loader = ControlledUsageLoader(started: [firstStarted, secondStarted])
        let model = SubscriptionStatusModel(defaults: defaults, loaders: [.codex: { try await loader.load() }])
        model.setEnabled(true, for: .codex)

        let firstRefresh = Task { @MainActor in await model.refresh(.codex) }
        await fulfillment(of: [firstStarted], timeout: 1)
        await loader.complete(
            call: 0,
            with: .success(SubscriptionUsage(primary: Self.window(percent: 99)))
        )
        _ = await firstRefresh.value

        let secondRefresh = Task { @MainActor in await model.refresh(.codex) }
        await fulfillment(of: [secondStarted], timeout: 1)
        let currentUsage = SubscriptionUsage(primary: Self.window(percent: 22))
        await loader.complete(call: 1, with: .success(currentUsage))
        _ = await secondRefresh.value

        XCTAssertEqual(model.state(for: .codex), .available(currentUsage))
    }

    func testConcurrentRefreshDoesNotStartSecondProviderLoad() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstLoaderStarted = expectation(description: "first loader started")
        let loader = ControlledUsageLoader(started: [firstLoaderStarted])
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.claude: { try await loader.load() }]
        )
        model.setEnabled(true, for: .claude)

        let firstRefresh = Task { @MainActor in
            await model.refresh(.claude)
        }
        await fulfillment(of: [firstLoaderStarted], timeout: 1)

        let didStartSecondRefresh = await model.refresh(.claude)

        let callCount = await loader.currentCallCount()
        XCTAssertFalse(didStartSecondRefresh)
        XCTAssertEqual(
            callCount,
            1,
            "Concurrent refreshes must not retain multiple provider loaders."
        )

        let usage = SubscriptionUsage(primary: Self.window(percent: 42))
        await loader.completeAll(with: .success(usage))
        _ = await firstRefresh.value

        XCTAssertEqual(model.state(for: .claude), .available(usage))
    }

    func testDisablingDuringRefreshPreventsLateCompletionFromPublishing() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let started = expectation(description: "loader started")
        let loader = ControlledUsageLoader(started: [started])
        let model = SubscriptionStatusModel(defaults: defaults, loaders: [.claude: { try await loader.load() }])
        model.setEnabled(true, for: .claude)
        let refresh = Task { @MainActor in await model.refresh(.claude) }

        await fulfillment(of: [started], timeout: 1)
        model.setEnabled(false, for: .claude)
        await loader.complete(call: 0, with: .success(SubscriptionUsage(primary: Self.window(percent: 75))))
        _ = await refresh.value

        XCTAssertEqual(model.state(for: .claude), .disabled)
    }

    func testLoaderFailureIsSanitizedAndPersistsNoFailureOrUsageData() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secret = "sk-ant-do-not-store"
        let model = SubscriptionStatusModel(defaults: defaults, loaders: [
            .claude: { throw RawAdapterFailure.output("stderr: \(secret)") },
        ])
        model.setEnabled(true, for: .claude)

        await model.refresh(.claude)

        XCTAssertEqual(model.state(for: .claude), .unavailable(message: "Unable to load Claude usage."))
        let persisted = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(Set(persisted.keys), [SubscriptionStatusModel.enabledProvidersDefaultsKey])
        XCTAssertFalse(String(describing: persisted).contains(secret))
    }

    func testUnsupportedProviderExplainsThatSubscriptionQuotaIsUnavailable() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SubscriptionStatusModel(defaults: defaults, loaders: [
            .claude: { throw ProviderUsageClientError.unsupportedResponse },
        ])
        model.setEnabled(true, for: .claude)

        await model.refresh(.claude)

        XCTAssertEqual(
            model.state(for: .claude),
            .unavailable(message: "Claude CLI가 구독 사용량을 제공하지 않습니다.")
        )
    }

    func testActivationRefreshUsesOrcaFiveMinuteStalenessThreshold() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = TestNow(Date(timeIntervalSince1970: 1_700_000_000))
        let calls = CallCounter()
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.codex: {
                await calls.increment()
                return SubscriptionUsage(primary: Self.window(percent: 9))
            }],
            now: clock.now
        )
        model.setEnabled(true, for: .codex)

        await model.refreshIfNeeded()
        var callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 1)

        clock.advance(by: 299)
        await model.refreshIfNeeded()
        callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 1)

        clock.advance(by: 1)
        await model.refreshIfNeeded()
        callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 2)
    }

    func testProviderFailureUsesOrcaExponentialActivationBackoff() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = TestNow(Date(timeIntervalSince1970: 1_700_000_000))
        let calls = CallCounter()
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.claude: {
                await calls.increment()
                throw ProviderUsageClientError.httpStatus(503)
            }],
            now: clock.now
        )
        model.setEnabled(true, for: .claude)

        await model.refreshIfNeeded()
        var callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 1)

        clock.advance(by: 29)
        await model.refreshIfNeeded()
        callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 1)

        clock.advance(by: 1)
        await model.refreshIfNeeded()
        callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 2)

        clock.advance(by: 59)
        await model.refreshIfNeeded()
        callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 2)

        clock.advance(by: 1)
        await model.refreshIfNeeded()
        callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 3)
    }

    func testPollingStartsImmediatelyAndRefreshesOnInjectedOrcaCadenceTick() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = TestNow(Date(timeIntervalSince1970: 1_700_000_000))
        let gate = PollGate()
        let firstRefresh = expectation(description: "immediate active refresh")
        let cadenceRefresh = expectation(description: "15-minute cadence refresh")
        let loader = PollingUsageLoader(expectations: [firstRefresh, cadenceRefresh])
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.codex: { await loader.load() }],
            now: clock.now,
            pollWait: { delay in await gate.wait(delay: delay) }
        )
        model.setEnabled(true, for: .codex)

        model.startPolling()
        await fulfillment(of: [firstRefresh], timeout: 1)

        XCTAssertEqual(SubscriptionStatusModel.pollInterval, 15 * 60)
        XCTAssertEqual(SubscriptionStatusModel.minimumRefetchInterval, 5 * 60)
        let requestedDelay = await gate.nextRequestedDelay()
        XCTAssertEqual(requestedDelay, SubscriptionStatusModel.pollInterval)
        clock.advance(by: requestedDelay)
        await gate.tick()
        await fulfillment(of: [cadenceRefresh], timeout: 1)

        model.stopPolling()
        await gate.tick()
    }

    func testPollingAutomaticallyWakesAtProviderFailureBackoffDeadlines() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = TestNow(Date(timeIntervalSince1970: 1_700_000_000))
        let gate = PollGate()
        let firstFailure = expectation(description: "initial failure")
        let secondFailure = expectation(description: "30-second retry failure")
        let loader = FailingPollingLoader(expectations: [firstFailure, secondFailure])
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.claude: { try await loader.load() }],
            now: clock.now,
            pollWait: { delay in await gate.wait(delay: delay) }
        )
        model.setEnabled(true, for: .claude)

        model.startPolling()
        await fulfillment(of: [firstFailure], timeout: 1)
        let firstDelay = await gate.nextRequestedDelay()
        XCTAssertEqual(firstDelay, 30)

        clock.advance(by: firstDelay)
        await gate.tick()
        await fulfillment(of: [secondFailure], timeout: 1)
        let secondDelay = await gate.nextRequestedDelay()
        XCTAssertEqual(secondDelay, 60)

        model.stopPolling()
        await gate.tick()
    }

    func testStoppingPollingCancelsInFlightProviderRefresh() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let started = expectation(description: "provider refresh started")
        let cancelled = expectation(description: "provider refresh cancelled")
        let loader = CancellationAwareUsageLoader(started: started, cancelled: cancelled)
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.codex: { try await loader.load() }]
        )
        model.setEnabled(true, for: .codex)

        model.startPolling()
        await fulfillment(of: [started], timeout: 1)
        model.stopPolling()

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertNotEqual(
            model.state(for: .codex),
            .available(SubscriptionUsage(primary: Self.window(percent: 100)))
        )
    }

    func testManualFailureWakesSleepingPollerForThirtySecondRetry() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = TestNow(Date(timeIntervalSince1970: 1_700_000_000))
        let gate = PollGate()
        let calls = CallCounter()
        let model = SubscriptionStatusModel(
            defaults: defaults,
            loaders: [.claude: {
                await calls.increment()
                throw ProviderUsageClientError.httpStatus(503)
            }],
            now: clock.now,
            pollWait: { delay in await gate.wait(delay: delay) },
            pollWake: { await gate.tick() }
        )

        model.startPolling()
        let initialDelay = await gate.nextRequestedDelay()
        XCTAssertEqual(initialDelay, SubscriptionStatusModel.pollInterval)

        model.setEnabled(true, for: .claude)
        await model.refresh(.claude)

        let retryDelay = await gate.nextRequestedDelay()
        XCTAssertEqual(retryDelay, 30)
        let callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 1)

        model.stopPolling()
        await gate.tick()
    }

    func testPollingWakeSignalRemainsSuspendedAfterEarlierTimerWins() async {
        let signal = PollingWakeSignal()
        await signal.wait(for: 0)

        let secondWaitStarted = expectation(description: "second wait started")
        let returnedBeforeSignal = expectation(description: "second wait returned before signal")
        returnedBeforeSignal.isInverted = true
        let secondWaitFinished = expectation(description: "second wait finished after signal")
        let releaseGate = PollingReturnGate()
        let secondWait = Task {
            secondWaitStarted.fulfill()
            await signal.wait(for: 60)
            if await !releaseGate.isReleased {
                returnedBeforeSignal.fulfill()
            }
            secondWaitFinished.fulfill()
        }

        await fulfillment(of: [secondWaitStarted], timeout: 1)
        await fulfillment(of: [returnedBeforeSignal], timeout: 0.05)

        await releaseGate.release()
        signal.signal()
        await fulfillment(of: [secondWaitFinished], timeout: 1)
        await secondWait.value
    }

    nonisolated private static func window(
        name: String = "Five hour",
        percent: Double,
        resetOffset: TimeInterval = 3_600
    ) -> SubscriptionUsageWindow {
        SubscriptionUsageWindow(
            name: name,
            usedPercent: percent,
            resetsAt: Date(timeIntervalSince1970: 1_700_000_000 + resetOffset)
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SubscriptionStatusModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private enum RawAdapterFailure: Error {
    case output(String)
}

private actor CallCounter {
    private var value = 0
    func increment() { value += 1 }
    func currentValue() -> Int { value }
}

private actor PollingReturnGate {
    private(set) var isReleased = false

    func release() {
        isReleased = true
    }
}

private final class TestNow: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: @Sendable () -> Date {
        { [self] in lock.withLock { date } }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

private actor PollGate {
    private var pendingTicks = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var requestedDelays: [TimeInterval] = []
    private var delayObservers: [CheckedContinuation<TimeInterval, Never>] = []

    func wait(delay: TimeInterval) async {
        if delayObservers.isEmpty {
            requestedDelays.append(delay)
        } else {
            delayObservers.removeFirst().resume(returning: delay)
        }
        if pendingTicks > 0 {
            pendingTicks -= 1
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func nextRequestedDelay() async -> TimeInterval {
        if !requestedDelays.isEmpty {
            return requestedDelays.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            delayObservers.append(continuation)
        }
    }

    func tick() {
        if continuations.isEmpty {
            pendingTicks += 1
        } else {
            continuations.removeFirst().resume()
        }
    }
}

private actor FailingPollingLoader {
    private let expectations: [XCTestExpectation]
    private var call = 0

    init(expectations: [XCTestExpectation]) {
        self.expectations = expectations
    }

    func load() throws -> SubscriptionUsage {
        expectations[call].fulfill()
        call += 1
        throw ProviderUsageClientError.httpStatus(503)
    }
}

private final class CancellationAwareUsageLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation
    private var continuation: CheckedContinuation<SubscriptionUsage, Error>?

    init(started: XCTestExpectation, cancelled: XCTestExpectation) {
        self.started = started
        self.cancelled = cancelled
    }

    func load() async throws -> SubscriptionUsage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                started.fulfill()
            }
        } onCancel: {
            let suspended = lock.withLock {
                let suspended = continuation
                continuation = nil
                return suspended
            }
            suspended?.resume(throwing: CancellationError())
            cancelled.fulfill()
        }
    }
}

private actor PollingUsageLoader {
    private let expectations: [XCTestExpectation]
    private var call = 0

    init(expectations: [XCTestExpectation]) {
        self.expectations = expectations
    }

    func load() -> SubscriptionUsage {
        expectations[call].fulfill()
        call += 1
        return SubscriptionUsage(
            primary: SubscriptionUsageWindow(
                name: "7 days",
                usedPercent: Double(call),
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
    }
}

private actor ControlledUsageLoader {
    private let started: [XCTestExpectation]
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<SubscriptionUsage, Error>] = [:]

    init(started: [XCTestExpectation]) {
        self.started = started
    }

    func load() async throws -> SubscriptionUsage {
        let call = nextCall
        nextCall += 1
        if started.indices.contains(call) {
            started[call].fulfill()
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func currentCallCount() -> Int {
        nextCall
    }

    func complete(call: Int, with result: Result<SubscriptionUsage, Error>) {
        guard let continuation = continuations.removeValue(forKey: call) else {
            XCTFail("No suspended loader call \(call)")
            return
        }
        continuation.resume(with: result)
    }

    func completeAll(with result: Result<SubscriptionUsage, Error>) {
        let suspended = continuations.values
        continuations.removeAll()
        for continuation in suspended {
            continuation.resume(with: result)
        }
    }
}
