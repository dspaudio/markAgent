import XCTest
@testable import ma

final class AgentTimelineStoreTests: XCTestCase {
    @MainActor
    func testRecordsNewestEventsFirstWithStableMetadata() {
        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 100))

        store.record(.terminalCreated(directory: URL(fileURLWithPath: "/tmp/repo")))
        store.record(.markdownOpened(url: URL(fileURLWithPath: "/tmp/repo/plan.md")))

        XCTAssertEqual(store.events.map(\.title), ["마크다운 열림", "터미널 탭"])
        XCTAssertEqual(store.events.first?.detail, "plan.md")
        XCTAssertEqual(store.events.last?.detail, "/tmp/repo")
        XCTAssertEqual(store.events.map(\.timestamp), [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 100)])
    }

    @MainActor
    func testRecordsGitDiffFocusWithRelativePath() {
        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 200))

        store.record(.gitDiffFocused(relativePath: "Sources/App/main.swift"))

        XCTAssertEqual(store.events.first?.kind, .gitDiff)
        XCTAssertEqual(store.events.first?.title, "Diff 포커스")
        XCTAssertEqual(store.events.first?.detail, "Sources/App/main.swift")
    }

    @MainActor
    func testKeepsMostRecentEventsWithinLimit() {
        let store = AgentTimelineStore(limit: 2, now: Date(timeIntervalSince1970: 300))

        store.record(.terminalCreated(directory: URL(fileURLWithPath: "/tmp/one")))
        store.record(.terminalCreated(directory: URL(fileURLWithPath: "/tmp/two")))
        store.record(.terminalCreated(directory: URL(fileURLWithPath: "/tmp/three")))

        XCTAssertEqual(store.events.map(\.detail), ["/tmp/three", "/tmp/two"])
    }

    @MainActor
    func testRuntimeEventsStayInMemoryWithoutDirtyingSharedTimelineFiles() throws {
        let repository = try makeTemporaryDirectory(prefix: "AgentTimelineStore-Runtime")
        defer { try? FileManager.default.removeItem(at: repository) }
        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 400))

        store.configureRepositoryRoot(repository)
        store.record(.markdownOpened(url: repository.appendingPathComponent("plans/review.md")))
        store.record(.gitDiffFocused(relativePath: "Sources/Core/AgentTimelineStore.swift"))

        XCTAssertEqual(store.events.map(\.kind), [.gitDiff, .markdown])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent(".agents/timeline.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent(".agents/timeline.md").path))
    }

    @MainActor
    func testPersistsSharedChangeSummaryToAgentsJSONLAndMarkdownSummary() throws {
        let repository = try makeTemporaryDirectory(prefix: "AgentTimelineStore-Persist")
        defer { try? FileManager.default.removeItem(at: repository) }
        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 450))
        let changes = AgentTimelineChanges(
            files: [AgentTimelineChangedFile(path: "Sources/Core/AgentTimelineStore.swift", insertions: 10, deletions: 2)],
            insertions: 10,
            deletions: 2
        )

        store.configureRepositoryRoot(repository)
        store.record(.changeSummary(title: "작업 요약", detail: "Timeline 공유 정책 정리", changes: changes))

        let jsonlURL = repository.appendingPathComponent(".agents/timeline.jsonl")
        let markdownURL = repository.appendingPathComponent(".agents/timeline.md")
        let jsonl = try String(contentsOf: jsonlURL, encoding: .utf8)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        XCTAssertEqual(jsonl.split(whereSeparator: \.isNewline).count, 1)
        XCTAssertTrue(jsonl.contains("change_summary"))
        XCTAssertTrue(markdown.contains("# Agent Timeline"))
        XCTAssertTrue(markdown.contains("Timeline 공유 정책 정리"))
        XCTAssertTrue(markdown.contains("Sources/Core/AgentTimelineStore.swift"))
    }

    @MainActor
    func testLoadsPersistedEventsAndSkipsBrokenJSONLLines() throws {
        let repository = try makeTemporaryDirectory(prefix: "AgentTimelineStore-Load")
        defer { try? FileManager.default.removeItem(at: repository) }
        let agentsDirectory = repository.appendingPathComponent(".agents")
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let jsonlURL = agentsDirectory.appendingPathComponent("timeline.jsonl")
        let validLine = """
        {"detail":"Timeline 공유 정책 정리","id":"00000000-0000-0000-0000-000000000001","kind":"change_summary","repositoryRoot":"\(repository.path)","source":"MarkAgent","timestamp":"1970-01-01T00:08:20Z","title":"작업 요약","version":1}
        """
        try ("not-json\n" + validLine + "\n").write(to: jsonlURL, atomically: true, encoding: .utf8)

        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 500))
        store.configureRepositoryRoot(repository)

        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.detail, "Timeline 공유 정책 정리")
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
