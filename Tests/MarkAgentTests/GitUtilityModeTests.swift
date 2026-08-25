import XCTest
@testable import ma

final class GitUtilityModeTests: XCTestCase {
    @MainActor
    func testGroupDefaultsToHistoryMode() {
        XCTAssertEqual(TabGroupState().gitUtilityMode, .history)
    }

    @MainActor
    func testHistoryAndChangesModesAreBothReachable() {
        let group = TabGroupState()

        group.selectGitUtilityMode(.changes)
        XCTAssertEqual(group.gitUtilityMode, .changes)

        group.selectGitUtilityMode(.history)
        XCTAssertEqual(group.gitUtilityMode, .history)
    }

    @MainActor
    func testModesAndOwnedGitStoresAreIsolatedAcrossGroups() {
        let first = TabGroupState()
        let second = TabGroupState()
        let firstHistoryStore = first.gitHistoryStore
        let firstDiffState = first.gitDiffState
        let firstTimelineStore = first.timelineStore

        first.selectGitUtilityMode(.changes)

        XCTAssertEqual(first.gitUtilityMode, .changes)
        XCTAssertEqual(second.gitUtilityMode, .history)
        XCTAssertTrue(first.gitHistoryStore === firstHistoryStore)
        XCTAssertTrue(first.gitDiffState === firstDiffState)
        XCTAssertTrue(first.timelineStore === firstTimelineStore)
        XCTAssertTrue(first.gitHistoryStore !== second.gitHistoryStore)
        XCTAssertTrue(first.gitDiffState !== second.gitDiffState)
        XCTAssertTrue(first.timelineStore !== second.timelineStore)
    }
}
