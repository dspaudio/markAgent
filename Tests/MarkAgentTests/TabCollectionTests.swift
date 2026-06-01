import XCTest
@testable import ma

final class TabCollectionTests: XCTestCase {
    @MainActor
    func testShowGitDiffTabReusesExistingDiffTabForExplicitOpenAction() {
        let tabs = TabCollection()
        let state = GitDiffState()

        let firstTab = tabs.showGitDiffTab(state: state)
        _ = tabs.createMarkdownTab(fileURL: nil)
        let secondTab = tabs.showGitDiffTab(state: state)

        XCTAssertEqual(firstTab.id, secondTab.id)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeTabID, firstTab.id)
    }
}
