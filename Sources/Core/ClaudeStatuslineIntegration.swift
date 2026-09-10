import CryptoKit
import Darwin
import Foundation

enum ClaudeStatuslineIntegration {
    private static let scriptHeader = "#!/bin/sh\n# MarkAgent Claude status line integration\n"

    static func install(
        executableURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard executableURL.isFileURL,
              !executableURL.path.contains("\0"),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw IntegrationError.executableUnavailable
        }

        let paths = try Paths(homeDirectory: homeDirectory, environment: environment)
        let currentData = try readIfPresent(paths.settings)
        var settings = try decodeSettings(currentData)
        let currentStatusline = try statusline(in: settings)
        let previousRecord = try readRecord(paths)
        let ownsCurrentCommand = currentStatusline?["command"] as? String == paths.command
        if ownsCurrentCommand && previousRecord == nil {
            throw IntegrationError.backupUnavailable
        }

        let record = ownsCurrentCommand ? previousRecord : Record(
            settingsPath: paths.settings.path,
            settingsExisted: currentData != nil,
            originalStatusline: try currentStatusline.map(encodeSettings)
        )
        guard let record else { throw IntegrationError.backupUnavailable }
        let originalStatusline = try decodeOriginalStatusline(record)
        let originalCommand = originalStatusline?["command"] as? String
        let script = makeScript(executableURL: executableURL, originalCommand: originalCommand)
        var installedStatusline = currentStatusline ?? ["type": "command"]
        installedStatusline["command"] = paths.command
        settings["statusLine"] = installedStatusline
        let installedData = try encodeSettings(settings)

        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.directory.path)
        let previousScript = try readIfPresent(paths.script)
        let previousRecordData = try readIfPresent(paths.record)
        let recordEncoder = JSONEncoder()
        recordEncoder.outputFormatting = [.sortedKeys]
        do {
            try writePrivate(Data(script.utf8), to: paths.script, permissions: 0o700)
            try writePrivate(try recordEncoder.encode(record), to: paths.record, permissions: 0o600)
            guard try readIfPresent(paths.settings) == currentData else {
                throw IntegrationError.settingsChanged
            }
            if !ownsCurrentCommand {
                try FileManager.default.createDirectory(
                    at: paths.settings.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try writeSettings(installedData, to: paths.settings)
            }
        } catch {
            do {
                try restore(previousScript, at: paths.script, permissions: 0o700)
                try restore(previousRecordData, at: paths.record, permissions: 0o600)
            } catch {
                throw IntegrationError.backupRestorationFailed
            }
            throw error
        }
    }

    static func uninstall(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let paths = try Paths(homeDirectory: homeDirectory, environment: environment)
        guard let currentData = try readIfPresent(paths.settings) else { return }
        var settings = try decodeSettings(currentData)
        guard var currentStatusline = settings["statusLine"] as? [String: Any],
              currentStatusline["type"] as? String == "command",
              currentStatusline["command"] as? String == paths.command else { return }
        guard let record = try readRecord(paths) else { throw IntegrationError.backupUnavailable }

        let originalStatusline = try decodeOriginalStatusline(record)
        if let originalCommand = originalStatusline?["command"] {
            currentStatusline["command"] = originalCommand
            settings["statusLine"] = currentStatusline
        } else if currentStatusline.keys.allSatisfy({ $0 == "type" || $0 == "command" }) {
            settings.removeValue(forKey: "statusLine")
        } else {
            currentStatusline["command"] = ""
            settings["statusLine"] = currentStatusline
        }

        guard try readIfPresent(paths.settings) == currentData else {
            throw IntegrationError.settingsChanged
        }
        if !record.settingsExisted && settings.isEmpty {
            try FileManager.default.removeItem(at: paths.settings)
        } else {
            try writeSettings(encodeSettings(settings), to: paths.settings)
        }
    }

    static func isInstalled(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let paths = try? Paths(homeDirectory: homeDirectory, environment: environment),
              let data = try? readIfPresent(paths.settings),
              let settings = try? decodeSettings(data),
              let statusline = try? statusline(in: settings),
              statusline["command"] as? String == paths.command,
              (try? readRecord(paths)) != nil,
              let script = try? String(contentsOf: paths.script, encoding: .utf8) else { return false }
        return script.hasPrefix(scriptHeader)
    }

    private static func makeScript(executableURL: URL, originalCommand: String?) -> String {
        // 명령 치환이 제거하는 마지막 줄바꿈을 sentinel로 보존한다.
        let capture = "input=$(/bin/cat; printf '.')\ninput=${input%.}\n"
        let save = "printf '%s' \"$input\" | \(shellQuote(executableURL.path)) --claude-statusline >/dev/null 2>&1\n"
        let output = originalCommand.map {
            "printf '%s' \"$input\" | /bin/sh -c \(shellQuote($0))\n"
        } ?? "exit 0\n"
        return scriptHeader + capture + save + output
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private static func decodeSettings(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let settings = object as? [String: Any] else {
            throw IntegrationError.invalidSettings
        }
        return settings
    }

    private static func statusline(in settings: [String: Any]) throws -> [String: Any]? {
        guard let value = settings["statusLine"] else { return nil }
        guard let statusline = value as? [String: Any],
              statusline["type"] as? String == "command",
              let command = statusline["command"] as? String,
              !command.contains("\0") else {
            throw IntegrationError.unsupportedStatusline
        }
        return statusline
    }

    private static func encodeSettings(_ settings: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func readRecord(_ paths: Paths) throws -> Record? {
        guard let data = try readIfPresent(paths.record) else { return nil }
        guard let record = try? JSONDecoder().decode(Record.self, from: data),
              record.settingsPath == paths.settings.path else {
            throw IntegrationError.backupUnavailable
        }
        return record
    }

    private static func decodeOriginalStatusline(_ record: Record) throws -> [String: Any]? {
        guard let data = record.originalStatusline else { return nil }
        let original = try decodeSettings(data)
        return try statusline(in: ["statusLine": original])
    }

    private static func writeSettings(_ data: Data, to url: URL) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        try writePrivate(data, to: url, permissions: permissions)
    }

    private static func writePrivate(_ data: Data, to url: URL, permissions: Int) throws {
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".markagent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: permissions]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(temporaryURL.path, url.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func restore(_ data: Data?, at url: URL, permissions: Int) throws {
        if let data {
            try writePrivate(data, to: url, permissions: permissions)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private struct Record: Codable {
        let settingsPath: String
        let settingsExisted: Bool
        let originalStatusline: Data?
    }

    private struct Paths {
        let settings: URL
        let directory: URL
        let script: URL
        let record: URL

        var command: String { "/bin/sh " + shellQuote(script.path) }

        init(homeDirectory: URL, environment: [String: String]) throws {
            let configuredDirectory = environment["CLAUDE_CONFIG_DIR"] ?? ""
            guard !configuredDirectory.contains("\0") else { throw IntegrationError.invalidConfigDirectory }
            let configDirectory: URL
            if configuredDirectory.isEmpty || configuredDirectory == "~" {
                configDirectory = configuredDirectory.isEmpty
                    ? homeDirectory.appendingPathComponent(".claude") : homeDirectory
            } else if configuredDirectory.hasPrefix("~/") {
                configDirectory = homeDirectory.appendingPathComponent(String(configuredDirectory.dropFirst(2)))
            } else {
                configDirectory = URL(fileURLWithPath: configuredDirectory, relativeTo: homeDirectory)
            }
            settings = configDirectory.appendingPathComponent("settings.json").standardizedFileURL
            let identifier = SHA256.hash(data: Data(settings.path.utf8))
                .map { String(format: "%02x", $0) }.joined()
            directory = homeDirectory.appendingPathComponent("Library/Application Support/MarkAgent/ClaudeStatusline")
                .appendingPathComponent(identifier)
            script = directory.appendingPathComponent("markagent-statusline.sh")
            record = directory.appendingPathComponent("settings-backup.json")
        }
    }

    enum IntegrationError: LocalizedError {
        case executableUnavailable
        case invalidSettings
        case unsupportedStatusline
        case backupUnavailable
        case backupRestorationFailed
        case settingsChanged
        case invalidConfigDirectory

        var errorDescription: String? {
            switch self {
            case .executableUnavailable:
                String(localized: "MarkAgent 실행 파일을 찾을 수 없습니다.")
            case .invalidSettings:
                String(localized: "Claude settings.json이 올바른 JSON 객체가 아닙니다.")
            case .unsupportedStatusline:
                String(localized: "Claude의 기존 statusLine 형식을 지원하지 않습니다. 설정을 변경하지 않았습니다.")
            case .backupUnavailable:
                String(localized: "Claude 상태줄의 원본 설정 백업을 읽을 수 없습니다.")
            case .backupRestorationFailed:
                String(localized: "Claude 상태줄 설치 파일을 복구하지 못했습니다. 설정 백업을 확인해주세요.")
            case .settingsChanged:
                String(localized: "Claude 설정이 변경되어 작업을 중단했습니다. 다시 시도해주세요.")
            case .invalidConfigDirectory:
                String(localized: "CLAUDE_CONFIG_DIR 경로가 올바르지 않습니다.")
            }
        }
    }
}
