import Darwin
import Foundation

enum ClaudeStatuslineUsageError: Error, Equatable {
    case noData
    case staleData
    case malformedData
}

enum ClaudeStatuslineUsageStore {
    static let notificationName = Notification.Name("com.markagent.claudeUsageDidUpdate")
    static let maximumAge: TimeInterval = 60 * 60
    static let maximumDataSize = 1_048_576

    static func cacheURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/MarkAgent", isDirectory: true)
            .appendingPathComponent("claude-usage.json")
    }

    @discardableResult
    static func save(
        _ data: Data,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) throws -> Bool {
        let input: StatuslineInput = try decode(data)
        guard let windows = input.rateLimits, !windows.isEmpty else { return false }
        try windows.validate()
        try validateTimestamp(now.timeIntervalSince1970)

        let activeWindows = windows.active(at: now)
        guard !activeWindows.isEmpty else { throw ClaudeStatuslineUsageError.staleData }

        let snapshot = Snapshot(
            receivedAt: now.timeIntervalSince1970,
            windows: activeWindows
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sanitizedData = try encoder.encode(snapshot)
        try writeAtomically(sanitizedData, to: cacheURL(homeDirectory: homeDirectory))
        return true
    }

    static func load(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) throws -> SubscriptionUsage {
        let data = try readCache(at: cacheURL(homeDirectory: homeDirectory))
        let snapshot: Snapshot = try decode(data)
        try validateTimestamp(snapshot.receivedAt)
        try validateTimestamp(now.timeIntervalSince1970)
        try snapshot.windows.validate()
        guard !snapshot.windows.isEmpty,
              snapshot.receivedAt <= now.timeIntervalSince1970 else {
            throw ClaudeStatuslineUsageError.malformedData
        }
        guard now.timeIntervalSince1970 - snapshot.receivedAt <= maximumAge else {
            throw ClaudeStatuslineUsageError.staleData
        }

        let windows = snapshot.windows.active(at: now).usageWindows
        guard let primary = windows.first else { throw ClaudeStatuslineUsageError.staleData }
        return SubscriptionUsage(
            primary: primary,
            secondary: windows.dropFirst().first,
            observedAt: Date(timeIntervalSince1970: snapshot.receivedAt)
        )
    }

    private struct StatuslineInput: Decodable {
        let rateLimits: Windows?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }

    private struct Snapshot: Codable {
        let receivedAt: TimeInterval
        let windows: Windows
    }

    private struct Windows: Codable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }

        var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

        var usageWindows: [SubscriptionUsageWindow] {
            [
                fiveHour?.usageWindow(name: "5 hours"),
                sevenDay?.usageWindow(name: "7 days"),
            ].compactMap { $0 }
        }

        func validate() throws {
            try fiveHour?.validate()
            try sevenDay?.validate()
        }

        func active(at date: Date) -> Windows {
            Windows(
                fiveHour: fiveHour.flatMap { $0.resetsAt > date.timeIntervalSince1970 ? $0 : nil },
                sevenDay: sevenDay.flatMap { $0.resetsAt > date.timeIntervalSince1970 ? $0 : nil }
            )
        }
    }

    private struct Window: Codable {
        let usedPercentage: Double
        let resetsAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        func validate() throws {
            guard usedPercentage.isFinite, (0...100).contains(usedPercentage) else {
                throw ClaudeStatuslineUsageError.malformedData
            }
            try ClaudeStatuslineUsageStore.validateTimestamp(resetsAt)
        }

        func usageWindow(name: String) -> SubscriptionUsageWindow {
            SubscriptionUsageWindow(
                name: name,
                usedPercent: usedPercentage,
                resetsAt: Date(timeIntervalSince1970: resetsAt)
            )
        }
    }

    private static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        guard !data.isEmpty, data.count <= maximumDataSize else {
            throw ClaudeStatuslineUsageError.malformedData
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw ClaudeStatuslineUsageError.malformedData
        }
    }

    private static func validateTimestamp(_ value: TimeInterval) throws {
        guard value.isFinite, value > 0, value <= Date.distantFuture.timeIntervalSince1970 else {
            throw ClaudeStatuslineUsageError.malformedData
        }
    }

    private static func readCache(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw errno == ENOENT
                ? ClaudeStatuslineUsageError.noData
                : ClaudeStatuslineUsageError.malformedData
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0,
              metadata.st_size <= maximumDataSize else {
            throw ClaudeStatuslineUsageError.malformedData
        }
        do {
            let data = try handle.read(upToCount: maximumDataSize + 1) ?? Data()
            guard data.count <= maximumDataSize else {
                throw ClaudeStatuslineUsageError.malformedData
            }
            return data
        } catch {
            throw ClaudeStatuslineUsageError.malformedData
        }
    }

    private static func writeAtomically(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw ClaudeStatuslineUsageError.malformedData
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let temporaryURL = directory.appendingPathComponent(".claude-usage-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? manager.removeItem(at: temporaryURL)
        }
        guard fchmod(descriptor, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try handle.write(contentsOf: data)
        try handle.close()
        guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
