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
}
