import XCTest
@testable import ma

final class TabGroupStateTests: XCTestCase {
    @MainActor
    func testGroupsOwnIndependentGitTimelineAndHistoryState() {
        let first = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/one"))
        let second = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/two"))

        XCTAssertTrue(first.gitDiffState !== second.gitDiffState)
        XCTAssertTrue(first.timelineStore !== second.timelineStore)
        XCTAssertTrue(first.gitHistoryStore !== second.gitHistoryStore)
        XCTAssertNotEqual(first.id, second.id)
    }

    @MainActor
    func testWorkingDirectoryChangesAreScopedToOneGroup() {
        let first = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/one"))
        let second = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/two"))

        first.updateWorkingDirectory(URL(fileURLWithPath: "/tmp/changed"))

        XCTAssertEqual(first.workingDirectory?.path, "/tmp/changed")
        XCTAssertEqual(second.workingDirectory?.path, "/tmp/two")
    }

    @MainActor
    func testTimelineEventsDoNotLeakAcrossGroups() {
        let first = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/one"))
        let second = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/two"))

        first.recordTimeline(.terminalCreated(directory: URL(fileURLWithPath: "/tmp/one")))

        XCTAssertEqual(first.timelineStore.events.count, 1)
        XCTAssertTrue(second.timelineStore.events.isEmpty)
    }

    @MainActor
    func testShowSnippetsSidebarSelectsSnippetsAndRevealsRightUtility() {
        let group = TabGroupState()
        group.rightUtilityRoute.isVisible = false
        group.rightUtilityRoute.selectedTab = .gitHistory

        group.showSnippetsSidebar()

        XCTAssertTrue(group.rightUtilityRoute.isVisible)
        XCTAssertEqual(group.rightUtilityRoute.selectedTab, .snippets)
    }

    @MainActor
    func testShowSnippetsSidebarDoesNotRequireGitRepository() {
        let group = TabGroupState(workingDirectory: URL(fileURLWithPath: "/tmp/not-a-repository"))

        group.showSnippetsSidebar()

        XCTAssertTrue(group.rightUtilityRoute.isVisible)
        XCTAssertNil(group.gitDiffState.repositoryRoot)
        XCTAssertEqual(group.rightUtilityRoute.selectedTab, .snippets)
    }
}
