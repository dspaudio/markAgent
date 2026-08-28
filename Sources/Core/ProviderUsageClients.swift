import Foundation

enum ProviderUsageClientError: Error, Equatable, Sendable {
    case executableMissing
    case credentialsMissing
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
                let accessToken = try ClaudeOAuthCredentialReader.readAccessToken(
                    homeDirectory: homeDirectory
                )
                return try await ClaudeOAuthUsageClient.fetch(accessToken: accessToken)
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

enum ClaudeUsageClient {
    static func request(executableURL: URL, homeDirectory: URL) -> GitHistoryProcessRequest {
        GitHistoryProcessRequest(
            executableURL: executableURL,
            arguments: ["-p", "/usage", "--output-format", "json", "--no-session-persistence"],
            timeoutSeconds: 10,
            outputByteLimit: 1_048_576,
            environment: providerEnvironment(homeDirectory: homeDirectory) + [
                "TZ=UTC",
                "NO_COLOR=1",
                "CLAUDE_CODE_SKIP_PROMPT_HISTORY=1",
            ]
        )
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> SubscriptionUsage {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let response = object as? [String: Any],
              response["is_error"] as? Bool == false,
              (response["duration_api_ms"] as? NSNumber)?.doubleValue == 0,
              (response["num_turns"] as? NSNumber)?.intValue == 0,
              (response["total_cost_usd"] as? NSNumber)?.doubleValue == 0,
              let result = response["result"] as? String else {
            throw ProviderUsageClientError.unsupportedResponse
        }

        let pattern = #"^(Current session|Current week[^:]*):\s+(\d+(?:\.\d+)?)% used\s+·\s+resets\s+(.+?)\s+\(UTC\)$"#
        let expression = try NSRegularExpression(pattern: pattern)
        var windows: [SubscriptionUsageWindow] = []

        for line in result.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression.firstMatch(in: line, range: range),
                  match.numberOfRanges == 4,
                  let nameRange = Range(match.range(at: 1), in: line),
                  let percentRange = Range(match.range(at: 2), in: line),
                  let resetRange = Range(match.range(at: 3), in: line),
                  let percent = Double(line[percentRange]),
                  (0...100).contains(percent),
                  let resetDate = parseClaudeReset(String(line[resetRange]), now: now) else {
                continue
            }
            windows.append(
                SubscriptionUsageWindow(
                    name: String(line[nameRange]),
                    usedPercent: percent,
                    resetsAt: resetDate
                )
            )
        }

        guard let primary = windows.first else {
            throw ProviderUsageClientError.unsupportedResponse
        }
        return SubscriptionUsage(primary: primary, secondary: windows.dropFirst().first)
    }

    private static func parseClaudeReset(_ value: String, now: Date) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d 'at' ha yyyy"

        guard var date = formatter.date(from: "\(value) \(year)") else { return nil }
        if date < now.addingTimeInterval(-300),
           let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
            date = nextYear
        }
        return date
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
        if let snapshots = result["rateLimitsByLimitId"] as? [String: Any] {
            for key in snapshots.keys.sorted() {
                if let snapshot = snapshots[key] as? [String: Any],
                   snapshot["primary"] != nil || snapshot["secondary"] != nil {
                    return snapshot
                }
            }
        }
        return result["rateLimits"] as? [String: Any]
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
