import Foundation

enum RipgrepInstallError: LocalizedError, Equatable {
    case homebrewUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .homebrewUnavailable:
            return String(localized: "Homebrew를 찾을 수 없습니다.")
        case .commandFailed(let output):
            return output.isEmpty
                ? String(localized: "ripgrep 설치에 실패했습니다.")
                : output
        }
    }
}

enum RipgrepTool {
    static let executablePaths = [
        "/opt/homebrew/bin/rg",
        "/usr/local/bin/rg",
        "/usr/bin/rg",
    ]

    static let homebrewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static func executableURL(
        fileManager: FileManager = .default,
        paths: [String] = executablePaths
    ) -> URL? {
        paths.first { fileManager.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    static func homebrewURL(
        fileManager: FileManager = .default,
        paths: [String] = homebrewPaths
    ) -> URL? {
        paths.first { fileManager.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    static func installWithHomebrew(fileManager: FileManager = .default) async throws {
        guard let homebrewURL = homebrewURL(fileManager: fileManager) else {
            throw RipgrepInstallError.homebrewUnavailable
        }

        let logURL = fileManager.temporaryDirectory.appending(path: "markagent-ripgrep-install.log")
        let script = "\(shellQuote(homebrewURL.path)) install ripgrep > \(shellQuote(logURL.path)) 2>&1"

        let status = try await runShell(script)
        guard status == 0 else {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw RipgrepInstallError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func runShell(_ script: String) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
