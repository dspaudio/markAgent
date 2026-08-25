import XCTest
@testable import ma

final class RightSidebarTabTests: XCTestCase {
    func testMachineOrderRawValuesAndIdentifiersAreStable() {
        let tabs = RightSidebarTab.allCases

        XCTAssertEqual(tabs, [.snippets, .timeline, .gitHistory, .fileBrowser])
        XCTAssertEqual(tabs.map(\.rawValue), ["snippets", "timeline", "gitHistory", "fileBrowser"])
        XCTAssertEqual(tabs.map(\.id), ["snippets", "timeline", "gitHistory", "fileBrowser"])
        XCTAssertEqual(tabs.map(\.accessibilityIdentifier), [
            "right-utility-snippets",
            "right-utility-timeline",
            "right-utility-git-history",
            "right-utility-file-browser",
        ])
    }
}
