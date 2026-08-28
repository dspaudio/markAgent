import Foundation
import XCTest
@testable import ma

final class ProviderUsageClientTests: XCTestCase {
    func testClaudeParsesSubscriptionWindowsFromZeroTurnUsageResult() throws {
        let response = """
        {
          "is_error": false,
          "duration_api_ms": 0,
          "num_turns": 0,
          "total_cost_usd": 0,
          "result": "You are currently using your subscription.\\nCurrent session: 13% used · resets Aug 28 at 6am (UTC)\\nCurrent week (all models): 3% used · resets Sep 3 at 7am (UTC)"
        }
        """
        let now = try XCTUnwrap(Self.utcDate("2026-08-28T02:00:00Z"))

        let usage = try ClaudeUsageClient.parse(Data(response.utf8), now: now)

        XCTAssertEqual(usage.primary.name, "Current session")
        XCTAssertEqual(usage.primary.usedPercent, 13)
        XCTAssertEqual(usage.primary.resetsAt, Self.utcDate("2026-08-28T06:00:00Z"))
        XCTAssertEqual(usage.secondary?.name, "Current week (all models)")
        XCTAssertEqual(usage.secondary?.usedPercent, 3)
        XCTAssertEqual(usage.secondary?.resetsAt, Self.utcDate("2026-09-03T07:00:00Z"))
    }

    func testClaudeRejectsModelBackedOrMalformedUsageOutput() throws {
        let modelBacked = """
        {"is_error":false,"duration_api_ms":12,"num_turns":1,"total_cost_usd":0.01,"result":"Current session: 13% used · resets Aug 28 at 6am (UTC)"}
        """
        let malformed = """
        {"is_error":false,"duration_api_ms":0,"num_turns":0,"total_cost_usd":0,"result":"Current session: 130% used · resets Aug 28 at 6am (UTC)"}
        """
        let now = try XCTUnwrap(Self.utcDate("2026-08-28T02:00:00Z"))

        XCTAssertThrowsError(try ClaudeUsageClient.parse(Data(modelBacked.utf8), now: now))
        XCTAssertThrowsError(try ClaudeUsageClient.parse(Data(malformed.utf8), now: now))
    }

    func testCodexParsesPrimaryAndSecondaryRateLimitWindows() throws {
        let response = """
        {"id":1,"result":{"userAgent":"codex_cli_rs/0.149.0"}}
        {"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":null}}}
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1787886000},"secondary":{"usedPercent":3,"windowDurationMins":10080,"resetsAt":1788480114}},"rateLimitsByLimitId":{}}}
        """

        let usage = try CodexUsageClient.parse(Data(response.utf8))

        XCTAssertEqual(usage.primary.name, "5 hours")
        XCTAssertEqual(usage.primary.usedPercent, 12)
        XCTAssertEqual(usage.primary.resetsAt, Date(timeIntervalSince1970: 1_787_886_000))
        XCTAssertEqual(usage.secondary?.name, "7 days")
        XCTAssertEqual(usage.secondary?.usedPercent, 3)
    }

    func testCodexRejectsMissingMatchingResponseAndInvalidPercent() {
        let missing = Data(#"{"id":1,"result":{}}"#.utf8)
        let invalid = Data(
            #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":-1,"windowDurationMins":300,"resetsAt":1787886000}}}}"#.utf8
        )

        XCTAssertThrowsError(try CodexUsageClient.parse(missing))
        XCTAssertThrowsError(try CodexUsageClient.parse(invalid))
    }

    func testRequestsUseProviderOwnedAuthenticationWithoutSecrets() throws {
        let home = URL(fileURLWithPath: "/Users/example")
        let claude = ClaudeUsageClient.request(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            homeDirectory: home
        )
        let codex = CodexUsageClient.request(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            homeDirectory: home
        )

        XCTAssertEqual(
            claude.arguments,
            ["-p", "/usage", "--output-format", "json", "--no-session-persistence"]
        )
        XCTAssertTrue(claude.environment.contains("HOME=/Users/example"))
        XCTAssertTrue(claude.environment.contains("TZ=UTC"))

        XCTAssertEqual(codex.executableURL.path, "/usr/bin/expect")
        let script = try XCTUnwrap(codex.arguments.dropFirst().first)
        XCTAssertTrue(script.contains(#""method":"initialize""#))
        XCTAssertTrue(script.contains(#""method":"initialized""#))
        XCTAssertTrue(script.contains(#""method":"account/rateLimits/read""#))
        XCTAssertFalse(script.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(
            codex.environment.contains("MARKAGENT_CODEX_EXECUTABLE=/opt/homebrew/bin/codex")
        )
        XCTAssertFalse(script.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(script.localizedCaseInsensitiveContains("secret"))

        let hostilePath = "/tmp/codex}; exec /usr/bin/false; {"
        let hostile = CodexUsageClient.request(
            executableURL: URL(fileURLWithPath: hostilePath),
            homeDirectory: home
        )
        let hostileScript = try XCTUnwrap(hostile.arguments.dropFirst().first)
        XCTAssertFalse(hostileScript.contains(hostilePath))
        XCTAssertTrue(
            hostile.environment.contains("MARKAGENT_CODEX_EXECUTABLE=\(hostilePath)")
        )
    }

    func testClaudeOAuthCredentialsParseWithoutPersistingTokens() throws {
        let credentials = Data(
            #"{"claudeAiOauth":{"accessToken":"test-access","refreshToken":"test-refresh","expiresAt":123}}"#.utf8
        )

        XCTAssertEqual(ClaudeOAuthCredentialReader.parseAccessToken(credentials), "test-access")
        XCTAssertNil(ClaudeOAuthCredentialReader.parseAccessToken(Data(#"{"claudeAiOauth":{}}"#.utf8)))
    }

    func testClaudeOAuthRequestAndUsageResponseMatchOrcaContract() throws {
        let request = try ClaudeOAuthUsageClient.request(accessToken: "test-access")

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.0")

        let response = Data(
            #"{"five_hour":{"utilization":14,"resets_at":"2026-08-28T10:00:00.316669+00:00"},"seven_day":{"used_percentage":31,"resets_at":1788480114}}"#.utf8
        )
        let usage = try ClaudeOAuthUsageClient.parse(response)

        XCTAssertEqual(usage.primary.name, "5 hours")
        XCTAssertEqual(usage.primary.usedPercent, 14)
        XCTAssertEqual(
            usage.primary.resetsAt.timeIntervalSince1970,
            try XCTUnwrap(Self.utcDate("2026-08-28T10:00:00Z")).timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(usage.secondary?.name, "7 days")
        XCTAssertEqual(usage.secondary?.usedPercent, 31)
        XCTAssertEqual(usage.secondary?.resetsAt, Date(timeIntervalSince1970: 1_788_480_114))
    }

    func testProviderVersionUsesBoundedReadOnlyCommand() async {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/codex")

        let version = await ProviderExecutableLocator.version(
            executableURL: executableURL,
            runner: { request in
                XCTAssertEqual(request.executableURL, executableURL)
                XCTAssertEqual(request.arguments, ["--version"])
                XCTAssertEqual(request.timeoutSeconds, 3)
                XCTAssertEqual(request.outputByteLimit, 16_384)
                return GitHistoryRawOutput(
                    stdout: Data("codex-cli 0.149.0\n".utf8),
                    stderr: Data()
                )
            }
        )

        XCTAssertEqual(version, "codex-cli 0.149.0")
    }

    private static func utcDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
