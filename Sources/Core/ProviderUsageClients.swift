import Foundation

enum ProviderUsageClientError: Error, Equatable, Sendable {
    case executableMissing
    case httpStatus(Int)
    case malformedResponse
    case unsupportedResponse
}

enum ProviderUsageClients {
    static func liveLoaders(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        runner: @escaping GitHistoryCommandRunner = GitHistoryProcessRunner.run
    ) -> [SubscriptionProvider: SubscriptionStatusModel.Loader] {
        var loaders: [SubscriptionProvider: SubscriptionStatusModel.Loader] = [
            .claude: {
                try ClaudeStatuslineUsageStore.load(homeDirectory: homeDirectory)
            },
        ]

        if let codexURL = ProviderExecutableLocator.executableURL(
            for: .codex,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ) {
            loaders[.codex] = {
                let request = CodexUsageClient.request(
                    executableURL: codexURL,
                    homeDirectory: homeDirectory
                )
                let output = try await runner(request)
                return try CodexUsageClient.parse(output.stdout)
            }
        }

        return loaders
    }
}

enum ProviderExecutableLocator {
    static func executableURL(
        for provider: SubscriptionProvider,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        let executableName = provider.rawValue
        let candidates = [
            homeDirectory.appendingPathComponent(".local/bin/\(executableName)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(executableName)"),
            URL(fileURLWithPath: "/usr/local/bin/\(executableName)"),
            URL(fileURLWithPath: "/usr/bin/\(executableName)"),
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func version(
        executableURL: URL,
        runner: @escaping GitHistoryCommandRunner = GitHistoryProcessRunner.run
    ) async -> String? {
        let request = GitHistoryProcessRequest(
            executableURL: executableURL,
            arguments: ["--version"],
            timeoutSeconds: 3,
            outputByteLimit: 16_384
        )
        guard let output = try? await runner(request),
              let text = String(data: output.stdout, encoding: .utf8) else {
            return nil
        }
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }
}

enum CodexUsageClient {
    static func request(executableURL: URL, homeDirectory: URL) -> GitHistoryProcessRequest {
        let initialize = #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"mark-agent","title":"MarkAgent","version":"1.0.0"}}}"#
        let initialized = #"{"method":"initialized","params":{}}"#
        let readRateLimits = #"{"method":"account/rateLimits/read","id":2,"params":{}}"#
        let script = """
        set timeout 10
        log_user 0
        spawn -noecho $env(MARKAGENT_CODEX_EXECUTABLE) app-server --stdio
        send -- {\(initialize)\r}
        expect {
            -re {"id":1,"result"} {}
            timeout { exit 124 }
            eof { exit 125 }
        }
        send -- {\(initialized)\r}
        send -- {\(readRateLimits)\r}
        expect {
            -re {"id":2,"result":[^\r\n]*\\}\r?\n} {
                puts $expect_out(buffer)
            }
            timeout { exit 124 }
            eof { exit 125 }
        }
        close
        wait
        exit 0
        """

        return GitHistoryProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/expect"),
            arguments: ["-c", script],
            timeoutSeconds: 15,
            outputByteLimit: 1_048_576,
            environment: providerEnvironment(homeDirectory: homeDirectory) + [
                "MARKAGENT_CODEX_EXECUTABLE=\(executableURL.path)",
            ]
        )
    }

    static func parse(_ data: Data) throws -> SubscriptionUsage {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProviderUsageClientError.malformedResponse
        }

        for line in text.split(whereSeparator: \.isNewline) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let message = value as? [String: Any],
                  (message["id"] as? NSNumber)?.intValue == 2,
                  let result = message["result"] as? [String: Any],
                  let snapshot = preferredSnapshot(from: result) else {
                continue
            }
            return try usage(from: snapshot)
        }

        throw ProviderUsageClientError.malformedResponse
    }

    private static func preferredSnapshot(from result: [String: Any]) -> [String: Any]? {
        if let snapshot = result["rateLimits"] as? [String: Any] {
            return snapshot
        }
        if let snapshots = result["rateLimitsByLimitId"] as? [String: Any] {
            for key in snapshots.keys.sorted() {
                if let snapshot = snapshots[key] as? [String: Any],
                   snapshot["primary"] != nil || snapshot["secondary"] != nil {
                    return snapshot
                }
            }
        }
        return nil
    }

    private static func usage(from snapshot: [String: Any]) throws -> SubscriptionUsage {
        let windows = ["primary", "secondary"].compactMap { key -> SubscriptionUsageWindow? in
            guard let value = snapshot[key] as? [String: Any],
                  let percent = (value["usedPercent"] as? NSNumber)?.doubleValue,
                  (0...100).contains(percent),
                  let duration = (value["windowDurationMins"] as? NSNumber)?.intValue,
                  duration > 0,
                  let reset = (value["resetsAt"] as? NSNumber)?.doubleValue,
                  reset > 0 else {
                return nil
            }
            return SubscriptionUsageWindow(
                name: windowName(durationMinutes: duration),
                usedPercent: percent,
                resetsAt: Date(timeIntervalSince1970: reset)
            )
        }

        guard let primary = windows.first else {
            throw ProviderUsageClientError.malformedResponse
        }
        return SubscriptionUsage(primary: primary, secondary: windows.dropFirst().first)
    }

    private static func windowName(durationMinutes: Int) -> String {
        switch durationMinutes {
        case 300:
            return "5 hours"
        case 10_080:
            return "7 days"
        default:
            return "\(durationMinutes) minutes"
        }
    }
}

private func providerEnvironment(homeDirectory: URL) -> [String] {
    [
        "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "LC_ALL=en_US.UTF-8",
        "HOME=\(homeDirectory.path)",
    ]
}
