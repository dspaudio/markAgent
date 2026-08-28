import Foundation
import Observation

enum SubscriptionProvider: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case claude
    case codex

    var id: Self { self }

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

}

struct SubscriptionUsageWindow: Equatable, Sendable {
    let name: String
    let usedPercent: Double
    let resetsAt: Date
}

struct SubscriptionUsage: Equatable, Sendable {
    let primary: SubscriptionUsageWindow
    let secondary: SubscriptionUsageWindow?

    init(primary: SubscriptionUsageWindow, secondary: SubscriptionUsageWindow? = nil) {
        self.primary = primary
        self.secondary = secondary
    }

    var windows: [SubscriptionUsageWindow] {
        [primary, secondary].compactMap { $0 }
    }
}

enum SubscriptionProviderState: Equatable, Sendable {
    case disabled
    case loading
    case available(SubscriptionUsage)
    case unavailable(message: String)
}

@MainActor
@Observable
final class SubscriptionStatusModel {
    typealias Loader = @Sendable () async throws -> SubscriptionUsage
    typealias PollWait = @Sendable (TimeInterval) async -> Void
    typealias PollWake = @Sendable () async -> Void

    static let enabledProvidersDefaultsKey = "MarkAgent.subscriptionStatus.registeredProviders"
    static let pollInterval: TimeInterval = 15 * 60
    static let minimumRefetchInterval: TimeInterval = 5 * 60
    static let initialFailureRetryInterval: TimeInterval = 30
    static let maximumFailureRetryInterval: TimeInterval = 15 * 60

    private(set) var enabledProviders: [SubscriptionProvider]
    private var states: [SubscriptionProvider: SubscriptionProviderState]
    private let defaults: UserDefaults
    private let loaders: [SubscriptionProvider: Loader]
    private let now: @Sendable () -> Date
    private let pollWait: PollWait
    private let pollWake: PollWake
    private var refreshGenerations: [SubscriptionProvider: Int]
    private var lastAttemptDates: [SubscriptionProvider: Date]
    private var failureStreaks: [SubscriptionProvider: Int]
    private var retryDates: [SubscriptionProvider: Date]
    private var refreshTasks: [SubscriptionProvider: Task<SubscriptionUsage, Error>]
    private var pollingTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        loaders: [SubscriptionProvider: Loader],
        now: @escaping @Sendable () -> Date = Date.init,
        pollWait: PollWait? = nil,
        pollWake: PollWake? = nil
    ) {
        let wakeSignal = PollingWakeSignal()
        self.defaults = defaults
        self.loaders = loaders
        self.now = now
        self.pollWait = pollWait ?? { interval in
            await wakeSignal.wait(for: interval)
        }
        self.pollWake = pollWake ?? {
            wakeSignal.signal()
        }
        self.refreshGenerations = [:]
        self.lastAttemptDates = [:]
        self.failureStreaks = [:]
        self.retryDates = [:]
        self.refreshTasks = [:]

        let initialEnabledProviders: [SubscriptionProvider]
        if let storedProviders = defaults.stringArray(forKey: Self.enabledProvidersDefaultsKey) {
            initialEnabledProviders = SubscriptionProvider.allCases.filter {
                storedProviders.contains($0.rawValue)
            }
        } else {
            initialEnabledProviders = []
            defaults.set([], forKey: Self.enabledProvidersDefaultsKey)
        }
        self.enabledProviders = initialEnabledProviders

        self.states = Dictionary(
            uniqueKeysWithValues: SubscriptionProvider.allCases.map { provider in
                (
                    provider,
                    initialEnabledProviders.contains(provider)
                        ? .unavailable(message: "Not refreshed yet.")
                        : .disabled
                )
            }
        )
    }

    func state(for provider: SubscriptionProvider) -> SubscriptionProviderState {
        states[provider] ?? .disabled
    }

    func setEnabled(_ isEnabled: Bool, for provider: SubscriptionProvider) {
        refreshGenerations[provider, default: 0] += 1
        lastAttemptDates[provider] = nil
        failureStreaks[provider] = nil
        retryDates[provider] = nil

        if isEnabled {
            guard !enabledProviders.contains(provider) else { return }
            enabledProviders = SubscriptionProvider.allCases.filter {
                $0 == provider || enabledProviders.contains($0)
            }
            states[provider] = .unavailable(message: "Not refreshed yet.")
        } else {
            refreshTasks.removeValue(forKey: provider)?.cancel()
            enabledProviders.removeAll { $0 == provider }
            states[provider] = .disabled
        }

        defaults.set(enabledProviders.map(\.rawValue), forKey: Self.enabledProvidersDefaultsKey)
    }

    @discardableResult
    func refresh(_ provider: SubscriptionProvider) async -> Bool {
        guard enabledProviders.contains(provider) else {
            states[provider] = .disabled
            return false
        }

        if refreshTasks[provider] != nil {
            return false
        }

        refreshGenerations[provider, default: 0] += 1
        let generation = refreshGenerations[provider, default: 0]
        states[provider] = .loading

        guard let loader = loaders[provider] else {
            guard generation == refreshGenerations[provider] else { return true }
            await recordFailure(for: provider)
            states[provider] = .unavailable(message: "Unable to load \(provider.displayName) usage.")
            return true
        }

        let refreshTask = Task {
            try await loader()
        }
        refreshTasks[provider] = refreshTask
        defer {
            if generation == refreshGenerations[provider] {
                refreshTasks[provider] = nil
            }
        }

        do {
            let usage = try await refreshTask.value
            guard generation == refreshGenerations[provider],
                  enabledProviders.contains(provider) else {
                return true
            }
            lastAttemptDates[provider] = now()
            failureStreaks[provider] = nil
            retryDates[provider] = nil
            states[provider] = .available(usage)
        } catch {
            guard generation == refreshGenerations[provider],
                  enabledProviders.contains(provider) else {
                return true
            }
            await recordFailure(for: provider)
            let message: String
            if error as? ProviderUsageClientError == .unsupportedResponse {
                message = "\(provider.displayName) CLI가 구독 사용량을 제공하지 않습니다."
            } else {
                message = "Unable to load \(provider.displayName) usage."
            }
            states[provider] = .unavailable(message: message)
        }
        return true
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in enabledProviders {
                group.addTask { [weak self] in
                    _ = await self?.refresh(provider)
                }
            }
        }
    }

    func refreshIfNeeded() async {
        let currentDate = now()
        let dueProviders = enabledProviders.filter { provider in
            if let retryDate = retryDates[provider] {
                return currentDate >= retryDate
            }
            guard let lastAttemptDate = lastAttemptDates[provider] else {
                return true
            }
            return currentDate.timeIntervalSince(lastAttemptDate) >= Self.minimumRefetchInterval
        }

        await withTaskGroup(of: Void.self) { group in
            for provider in dueProviders {
                group.addTask { [weak self] in
                    _ = await self?.refresh(provider)
                }
            }
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        let pollWait = self.pollWait
        pollingTask = Task { [weak self] in
            await self?.refreshIfNeeded()
            while !Task.isCancelled {
                guard let delay = self?.nextPollingDelay() else { return }
                await pollWait(delay)
                guard !Task.isCancelled else { break }
                await self?.refreshIfNeeded()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        for refreshTask in refreshTasks.values {
            refreshTask.cancel()
        }
        refreshTasks.removeAll()
        for provider in enabledProviders {
            refreshGenerations[provider, default: 0] += 1
        }
    }

    private func nextPollingDelay() -> TimeInterval {
        let currentDate = now()
        let retryDelay = retryDates.values
            .map { max(0, $0.timeIntervalSince(currentDate)) }
            .min()
        return min(Self.pollInterval, retryDelay ?? Self.pollInterval)
    }

    private func recordFailure(for provider: SubscriptionProvider) async {
        let currentDate = now()
        let streak = min(failureStreaks[provider, default: 0] + 1, 8)
        let exponentialDelay = Self.initialFailureRetryInterval * pow(2, Double(streak - 1))
        let delay = min(exponentialDelay, Self.maximumFailureRetryInterval)
        lastAttemptDates[provider] = currentDate
        failureStreaks[provider] = streak
        retryDates[provider] = currentDate.addingTimeInterval(delay)
        if pollingTask != nil {
            await pollWake()
        }
    }
}

final class PollingWakeSignal: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
        let deadline: DispatchWorkItem
    }

    private let lock = NSLock()
    private var pendingSignal = false
    private var waiter: Waiter?

    func signal() {
        let resumedWaiter: Waiter? = lock.withLock {
            guard let waiter else {
                pendingSignal = true
                return nil
            }
            self.waiter = nil
            return waiter
        }
        resumedWaiter?.deadline.cancel()
        resumedWaiter?.continuation.resume()
    }

    func wait(for interval: TimeInterval) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let deadline = DispatchWorkItem { [weak self] in
                    self?.resumeWaiter(id: id)
                }
                let shouldResumeImmediately = lock.withLock {
                    guard !Task.isCancelled, !pendingSignal else {
                        pendingSignal = false
                        return true
                    }
                    waiter = Waiter(
                        id: id,
                        continuation: continuation,
                        deadline: deadline
                    )
                    return false
                }

                if shouldResumeImmediately {
                    continuation.resume()
                } else {
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + interval,
                        execute: deadline
                    )
                }
            }
        } onCancel: { [weak self] in
            self?.resumeWaiter(id: id)
        }
    }

    private func resumeWaiter(id: UUID) {
        let resumedWaiter: Waiter? = lock.withLock {
            guard waiter?.id == id else { return nil }
            let resumedWaiter = waiter
            waiter = nil
            return resumedWaiter
        }
        resumedWaiter?.deadline.cancel()
        resumedWaiter?.continuation.resume()
    }
}
