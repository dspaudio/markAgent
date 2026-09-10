import Foundation
import XCTest
@testable import ma

final class ProviderUsageClientTests: XCTestCase {
    func testClaudeLiveLoaderReadsLatestStatuslineCacheWithoutLaunchingCommand() async throws {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProviderUsageClientTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let loaders = ProviderUsageClients.liveLoaders(
            homeDirectory: homeDirectory,
            runner: { _ in
                XCTFail("Claude statusline 사용량 조회는 외부 명령을 실행하면 안 됩니다.")
                throw ProviderUsageClientError.unsupportedResponse
            }
        )
        let loader = try XCTUnwrap(loaders[.claude])
        let firstObservation = Date().addingTimeInterval(-120)

        for (usedPercent, observedAt) in [(12.5, firstObservation), (18.5, firstObservation.addingTimeInterval(60))] {
            let resetsAt = observedAt.addingTimeInterval(18_000)
            let input = try JSONSerialization.data(withJSONObject: [
                "rate_limits": [
                    "five_hour": [
                        "used_percentage": usedPercent,
                        "resets_at": resetsAt.timeIntervalSince1970,
                    ],
                ],
            ])
            XCTAssertTrue(try ClaudeStatuslineUsageStore.save(input, homeDirectory: homeDirectory, now: observedAt))
            let cacheURL = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: homeDirectory)
            let cacheBeforeRead = try Data(contentsOf: cacheURL)
            let modifiedBeforeRead = try cacheURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate

            let usage = try await loader()

            XCTAssertEqual(try Data(contentsOf: cacheURL), cacheBeforeRead)
            XCTAssertEqual(
                try cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                modifiedBeforeRead
            )
            XCTAssertEqual(usage.primary.name, "5 hours")
            XCTAssertEqual(usage.primary.usedPercent, usedPercent)
            XCTAssertEqual(usage.primary.resetsAt.timeIntervalSince1970, resetsAt.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(
                try XCTUnwrap(usage.observedAt).timeIntervalSince1970,
                observedAt.timeIntervalSince1970,
                accuracy: 0.001
            )
            XCTAssertNil(usage.secondary)
        }
    }

    func testClaudeLiveLoaderReportsMissingCacheWithoutLaunchingCommandOrCreatingFiles() async throws {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProviderUsageClientTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let loaders = ProviderUsageClients.liveLoaders(
            homeDirectory: homeDirectory,
            runner: { _ in
                XCTFail("statusline 캐시가 없어도 외부 명령을 실행하면 안 됩니다.")
                throw ProviderUsageClientError.unsupportedResponse
            }
        )
        let loader = try XCTUnwrap(loaders[.claude])

        do {
            _ = try await loader()
            XCTFail("statusline 캐시가 없으면 조회 실패를 반환해야 합니다.")
        } catch {
            XCTAssertEqual(error as? ClaudeStatuslineUsageError, .noData)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: homeDirectory.path))
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

    func testCodexPrefersAuthoritativeRateLimitsOverModelSpecificSnapshots() throws {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":43,"windowDurationMins":10080,"resetsAt":1789103202},"secondary":null},"rateLimitsByLimitId":{"base_model_inference":{"limitId":"base_model_inference","limitName":"gpt-reserve","primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1789367878},"secondary":null},"codex":{"limitId":"codex","primary":{"usedPercent":43,"windowDurationMins":10080,"resetsAt":1789103202},"secondary":null},"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1788781012},"secondary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1789367812}}}}}
        """

        let usage = try CodexUsageClient.parse(Data(response.utf8))

        XCTAssertEqual(usage.primary.name, "7 days")
        XCTAssertEqual(
            usage.primary.usedPercent,
            43,
            "Codex aggregate usage must not be replaced by the first model-specific snapshot"
        )
        XCTAssertEqual(usage.primary.resetsAt, Date(timeIntervalSince1970: 1_789_103_202))
        XCTAssertNil(usage.secondary)
    }

    func testCodexRejectsMissingMatchingResponseAndInvalidPercent() {
        let missing = Data(#"{"id":1,"result":{}}"#.utf8)
        let invalid = Data(
            #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":-1,"windowDurationMins":300,"resetsAt":1787886000}}}}"#.utf8
        )

        XCTAssertThrowsError(try CodexUsageClient.parse(missing))
        XCTAssertThrowsError(try CodexUsageClient.parse(invalid))
    }

    func testCodexRequestUsesProviderOwnedAuthenticationWithoutSecrets() throws {
        let home = URL(fileURLWithPath: "/Users/example")
        let codex = CodexUsageClient.request(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            homeDirectory: home
        )

        XCTAssertEqual(codex.executableURL.path, "/usr/bin/expect")
        XCTAssertTrue(codex.environment.contains("HOME=/Users/example"))
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
}
