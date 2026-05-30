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
    func testPersistsEventsToAgentsJSONLAndMarkdownSummary() throws {
        let repository = try makeTemporaryDirectory(prefix: "AgentTimelineStore-Persist")
        defer { try? FileManager.default.removeItem(at: repository) }
        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 400))

        store.configureRepositoryRoot(repository)
        store.record(.markdownOpened(url: repository.appendingPathComponent("plans/review.md")))
        store.record(.gitDiffFocused(relativePath: "Sources/Core/AgentTimelineStore.swift"))

        let jsonlURL = repository.appendingPathComponent(".agents/timeline.jsonl")
        let markdownURL = repository.appendingPathComponent(".agents/timeline.md")
        let jsonl = try String(contentsOf: jsonlURL, encoding: .utf8)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        XCTAssertEqual(jsonl.split(whereSeparator: \.isNewline).count, 2)
        XCTAssertTrue(jsonl.contains("markdown_opened"))
        XCTAssertTrue(jsonl.contains("git_diff_focused"))
        XCTAssertTrue(markdown.contains("# Agent Timeline"))
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
        {"detail":"Sources/App/main.swift","id":"00000000-0000-0000-0000-000000000001","kind":"git_diff_focused","repositoryRoot":"\(repository.path)","source":"MarkAgent","timestamp":"1970-01-01T00:08:20Z","title":"Diff 포커스","version":1}
        """
        try ("not-json\n" + validLine + "\n").write(to: jsonlURL, atomically: true, encoding: .utf8)

        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 500))
        store.configureRepositoryRoot(repository)

        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.detail, "Sources/App/main.swift")
    }

    @MainActor
    func testRecordsLatestCommitWithChangeSummaryOnlyOnce() async throws {
        let repository = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let store = AgentTimelineStore(now: Date(timeIntervalSince1970: 600))

        store.recordLatestCommitIfNeeded(repositoryRoot: repository)
        try await waitUntil { store.events.contains { $0.kind == .commit } }
        store.recordLatestCommitIfNeeded(repositoryRoot: repository)
        try await Task.sleep(for: .milliseconds(150))

        let commitEvents = store.events.filter { $0.kind == .commit }
        XCTAssertEqual(commitEvents.count, 1)
        XCTAssertEqual(commitEvents.first?.commit?.subject, "initial")
        XCTAssertEqual(commitEvents.first?.changes?.files.map(\.path), ["notes.md"])
        XCTAssertEqual(commitEvents.first?.changes?.insertions, 1)

        let markdown = try String(
            contentsOf: repository.appendingPathComponent(".agents/timeline.md"),
            encoding: .utf8
        )
        XCTAssertTrue(markdown.contains("커밋 `"))
        XCTAssertTrue(markdown.contains("notes.md"))
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeGitRepository() throws -> URL {
        let root = try makeTemporaryDirectory(prefix: "AgentTimelineStore-Git")
        _ = try runGit(["init"], in: root)
        try "base\n".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "notes.md"], in: root)
        _ = try runGit(["commit", "-m", "initial"], in: root)
        return root
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "LANG": "C",
            "GIT_AUTHOR_NAME": "MarkAgent",
            "GIT_AUTHOR_EMAIL": "markagent@example.com",
            "GIT_COMMITTER_NAME": "MarkAgent",
            "GIT_COMMITTER_EMAIL": "markagent@example.com",
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(domain: "AgentTimelineStoreTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: error.isEmpty ? output : error,
            ])
        }

        return output
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout {
                throw NSError(domain: "AgentTimelineStoreTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Timed out waiting for AgentTimelineStore update.",
                ])
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
