import Foundation
import XCTest
@testable import ma

final class ClaudeStatuslineUsageStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    func testRoundTripStoresOnlyUsageWindowsAndReceiptTime() throws {
        try withTemporaryHome { home in
            let input = Data("""
            {
              "session_id": "private-session",
              "transcript_path": "/private/transcript.jsonl",
              "workspace": {"current_dir": "/private/project"},
              "context_window": {"total_input_tokens": 123456},
              "accessToken": "test-only-secret",
              "rate_limits": {
                "five_hour": {"used_percentage": 23.5, "resets_at": 1789018000, "extra": "discard"},
                "seven_day": {"used_percentage": 41.2, "resets_at": 1789604800},
                "spend_limit": {"used_percentage": 99, "resets_at": 1789604800}
              }
            }
            """.utf8)

            XCTAssertTrue(try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: now))

            let usage = try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now.addingTimeInterval(10))
            XCTAssertEqual(usage.primary.name, "5 hours")
            XCTAssertEqual(usage.primary.usedPercent, 23.5)
            XCTAssertEqual(usage.primary.resetsAt.timeIntervalSince1970, 1_789_018_000)
            XCTAssertEqual(usage.secondary?.name, "7 days")
            XCTAssertEqual(usage.secondary?.usedPercent, 41.2)
            XCTAssertEqual(usage.observedAt, now)

            let cachedData = try Data(contentsOf: ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home))
            let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: cachedData) as? [String: Any])
            XCTAssertEqual(Set(snapshot.keys), ["receivedAt", "windows"])
            XCTAssertEqual(snapshot["receivedAt"] as? Double, now.timeIntervalSince1970)
            let windows = try XCTUnwrap(snapshot["windows"] as? [String: [String: Any]])
            XCTAssertEqual(Set(windows.keys), ["five_hour", "seven_day"])
            for window in windows.values {
                XCTAssertEqual(Set(window.keys), ["used_percentage", "resets_at"])
            }
            let cachedText = String(decoding: cachedData, as: UTF8.self)
            for forbidden in ["private", "tokens", "secret", "spend_limit", "extra"] {
                XCTAssertFalse(cachedText.contains(forbidden), forbidden)
            }
        }
    }

    func testEitherWindowCanBeIndependentlyAbsentOrNull() throws {
        for (key, name, other) in [("five_hour", "5 hours", "seven_day"), ("seven_day", "7 days", "five_hour")] {
            for omittedWindow in ["", ",\"\(other)\":null"] {
                try withTemporaryHome { home in
                    let input = Data("""
                    {"rate_limits":{"\(key)":{"used_percentage":0,"resets_at":1789018000}\(omittedWindow)}}
                    """.utf8)

                    XCTAssertTrue(try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: now))
                    let usage = try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now)
                    XCTAssertEqual(usage.primary.name, name)
                    XCTAssertEqual(usage.primary.usedPercent, 0)
                    XCTAssertNil(usage.secondary)
                }
            }
        }
    }

    func testAbsentRateLimitsPreserveExistingSnapshotWithoutInventingZeroUsage() throws {
        try withTemporaryHome { home in
            let missingPayloads = ["{}", #"{"rate_limits":null}"#, #"{"rate_limits":{}}"#,
                                   #"{"rate_limits":{"five_hour":null,"seven_day":null}}"#]
            for payload in missingPayloads {
                XCTAssertFalse(try ClaudeStatuslineUsageStore.save(Data(payload.utf8), homeDirectory: home, now: now))
            }
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now)) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .noData)
            }

            try ClaudeStatuslineUsageStore.save(validInput(percentage: 100), homeDirectory: home, now: now)
            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            let original = try Data(contentsOf: url)
            for payload in missingPayloads {
                XCTAssertFalse(try ClaudeStatuslineUsageStore.save(Data(payload.utf8), homeDirectory: home, now: now))
                XCTAssertEqual(try Data(contentsOf: url), original)
            }
            XCTAssertEqual(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now).primary.usedPercent, 100)
        }
    }

    func testSnapshotExpiresAfterOneHourWithoutExtendingReceiptTimeOnRead() throws {
        try withTemporaryHome { home in
            try ClaudeStatuslineUsageStore.save(validInput(), homeDirectory: home, now: now)

            let boundary = now.addingTimeInterval(ClaudeStatuslineUsageStore.maximumAge)
            XCTAssertEqual(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: boundary).observedAt, now)
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: boundary.addingTimeInterval(1))) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .staleData)
            }
        }
    }

    func testExpiredWindowsAreDroppedDuringSaveAndLoad() throws {
        try withTemporaryHome { home in
            let input = Data("""
            {"rate_limits":{
              "five_hour":{"used_percentage":12,"resets_at":1789000010},
              "seven_day":{"used_percentage":34,"resets_at":1789000020}
            }}
            """.utf8)
            try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: now)

            let firstReset = now.addingTimeInterval(10)
            let remaining = try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: firstReset)
            XCTAssertEqual(remaining.primary.name, "7 days")
            XCTAssertEqual(remaining.primary.usedPercent, 34)
            XCTAssertNil(remaining.secondary)
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now.addingTimeInterval(20))) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .staleData)
            }

            try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: firstReset)
            let snapshotText = String(decoding: try Data(contentsOf: ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)), as: UTF8.self)
            XCTAssertFalse(snapshotText.contains("five_hour"))
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: now.addingTimeInterval(20))) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .staleData)
            }
        }
    }

    func testMalformedInputNeverReplacesValidSnapshot() throws {
        try withTemporaryHome { home in
            try ClaudeStatuslineUsageStore.save(validInput(), homeDirectory: home, now: now)
            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            let original = try Data(contentsOf: url)
            var malformed = ["", "[]", "null", "{", #"{"rate_limits":false}"#, #"{"rate_limits":[]}"#]
            malformed += ["true", "[]", "\"wrong\"", "{}"].map {
                "{\"rate_limits\":{\"five_hour\":\($0)}}"
            }
            malformed += ["true", "false", "null", "\"12\"", "-1", "101", "1e999", "NaN"].map {
                "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":\($0),\"resets_at\":1789018000}}}"
            }
            malformed += ["true", "null", "\"1789018000\"", "-1", "0", "1e999", "1e100"].map {
                "{\"rate_limits\":{\"seven_day\":{\"used_percentage\":12,\"resets_at\":\($0)}}}"
            }
            malformed.append(#"{"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1789018000},"seven_day":{"used_percentage":false,"resets_at":1789604800}}}"#)

            for payload in malformed {
                XCTAssertThrowsError(try ClaudeStatuslineUsageStore.save(Data(payload.utf8), homeDirectory: home, now: now), payload) {
                    XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .malformedData, payload)
                }
                XCTAssertEqual(try Data(contentsOf: url), original, payload)
            }
        }
    }

    func testInputAndCacheReadsHaveInclusiveOneMiBSizeLimit() throws {
        try withTemporaryHome { home in
            var input = validInput()
            input.append(Data(repeating: 0x20, count: ClaudeStatuslineUsageStore.maximumDataSize - input.count))
            XCTAssertTrue(try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: now))

            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            let original = try Data(contentsOf: url)
            input.append(0x20)
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.save(input, homeDirectory: home, now: now)) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .malformedData)
            }
            XCTAssertEqual(try Data(contentsOf: url), original)

            var paddedCache = original
            paddedCache.append(Data(repeating: 0x20, count: ClaudeStatuslineUsageStore.maximumDataSize - original.count))
            try paddedCache.write(to: url)
            XCTAssertNoThrow(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now))
            paddedCache.append(0x20)
            try paddedCache.write(to: url)
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now)) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .malformedData)
            }
        }
    }

    func testMalformedAndFutureDatedCacheIsRejected() throws {
        try withTemporaryHome { home in
            try ClaudeStatuslineUsageStore.save(validInput(), homeDirectory: home, now: now)
            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            let malformed = [
                "", "{}", "[]",
                #"{"receivedAt":true,"windows":{}}"#,
                #"{"receivedAt":1789000000,"windows":{}}"#,
                #"{"receivedAt":1789000000,"windows":{"five_hour":{"used_percentage":true,"resets_at":1789018000}}}"#,
                #"{"receivedAt":1789000001,"windows":{"five_hour":{"used_percentage":12,"resets_at":1789018000}}}"#,
            ]
            for payload in malformed {
                try Data(payload.utf8).write(to: url)
                XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now), payload) {
                    XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .malformedData, payload)
                }
            }
        }
    }

    func testAtomicReplacementKeepsPrivatePermissionsAndLeavesOldInodeUntouched() throws {
        try withTemporaryHome { home in
            let manager = FileManager.default
            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            let directory = url.deletingLastPathComponent()
            try ClaudeStatuslineUsageStore.save(validInput(percentage: 12), homeDirectory: home, now: now)
            XCTAssertEqual(try permissions(at: directory), 0o700)
            XCTAssertEqual(try permissions(at: url), 0o600)

            let previousURL = home.appendingPathComponent("previous-snapshot.json")
            try manager.linkItem(at: url, to: previousURL)
            let original = try Data(contentsOf: previousURL)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

            try ClaudeStatuslineUsageStore.save(validInput(percentage: 34), homeDirectory: home, now: now)

            XCTAssertEqual(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now).primary.usedPercent, 34)
            XCTAssertEqual(try Data(contentsOf: previousURL), original)
            XCTAssertEqual(try permissions(at: directory), 0o700)
            XCTAssertEqual(try permissions(at: url), 0o600)
            XCTAssertEqual(try manager.contentsOfDirectory(atPath: directory.path), ["claude-usage.json"])
        }
    }

    func testCacheSymlinkIsNotReadAndSaveDoesNotWriteThroughIt() throws {
        try withTemporaryHome { home in
            let manager = FileManager.default
            try ClaudeStatuslineUsageStore.save(validInput(), homeDirectory: home, now: now)
            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            let target = home.appendingPathComponent("unrelated.json")
            try manager.moveItem(at: url, to: target)
            let original = try Data(contentsOf: target)
            try manager.createSymbolicLink(at: url, withDestinationURL: target)

            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now)) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .malformedData)
            }
            try ClaudeStatuslineUsageStore.save(validInput(percentage: 56), homeDirectory: home, now: now)
            XCTAssertEqual(try Data(contentsOf: target), original)
            XCTAssertEqual(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now).primary.usedPercent, 56)
        }
    }

    func testFailedReplacementCleansTemporaryFilesAndDirectoryCacheCannotBeRead() throws {
        try withTemporaryHome { home in
            let manager = FileManager.default
            let url = ClaudeStatuslineUsageStore.cacheURL(homeDirectory: home)
            try manager.createDirectory(at: url, withIntermediateDirectories: true)

            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.save(validInput(), homeDirectory: home, now: now))
            XCTAssertEqual(try manager.contentsOfDirectory(atPath: url.deletingLastPathComponent().path), ["claude-usage.json"])
            XCTAssertThrowsError(try ClaudeStatuslineUsageStore.load(homeDirectory: home, now: now)) {
                XCTAssertEqual($0 as? ClaudeStatuslineUsageError, .malformedData)
            }
        }
    }

    private func validInput(percentage: Double = 12) -> Data {
        Data("""
        {"rate_limits":{"five_hour":{"used_percentage":\(percentage),"resets_at":1789018000}}}
        """.utf8)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func withTemporaryHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeStatuslineUsageStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }
}
