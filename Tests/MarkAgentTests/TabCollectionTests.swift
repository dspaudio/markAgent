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

    @MainActor
    func testTerminalTabCreatesActiveGroup() {
        let tabs = TabCollection()
        let directory = URL(fileURLWithPath: "/tmp/terminal-one")

        let tab = tabs.createTerminalTab(workingDirectory: directory)

        XCTAssertEqual(tabs.activeTabGroup?.id, tab.groupState.id)
        XCTAssertEqual(tab.groupState.workingDirectory?.path, directory.path)
        XCTAssertEqual(tabs.tabGroups.count, 1)
    }

    @MainActor
    func testMarkdownTabOpenedFromTerminalStaysInActiveTerminalGroup() {
        let tabs = TabCollection()
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-two"))
        let thirdTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-three"))

        tabs.selectTab(id: secondTerminal.id)
        let markdown = tabs.createMarkdownTab(fileURL: URL(fileURLWithPath: "/tmp/terminal-two/note.md"))

        XCTAssertEqual(markdown.groupID, secondTerminal.groupState.id)
        XCTAssertEqual(tabs.tabs.map(\.id), [firstTerminal.id, secondTerminal.id, markdown.id, thirdTerminal.id])
    }

    @MainActor
    func testClosingActiveChildTabReturnsToParentTabInSameGroup() async {
        let tabs = TabCollection()
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))
        let markdown = tabs.createMarkdownTab(fileURL: URL(fileURLWithPath: "/tmp/terminal-one/note.md"))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-two"))

        tabs.selectTab(id: markdown.id)
        let closed = await tabs.closeActiveTab()

        XCTAssertTrue(closed)
        XCTAssertEqual(tabs.activeTabID, firstTerminal.id)
        XCTAssertNotEqual(tabs.activeTabID, secondTerminal.id)
    }

    @MainActor
    func testGitDiffTabForActiveGroupSharesGroupState() {
        let tabs = TabCollection()
        let terminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))

        let diff = tabs.showGitDiffTabForActiveGroup()

        XCTAssertTrue(diff.state === terminal.groupState.gitDiffState)
        XCTAssertTrue(diff.groupState === terminal.groupState)
    }

    @MainActor
    func testGitDiffTabForActiveGroupReusesSameGroupTab() {
        let tabs = TabCollection()
        _ = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))

        let firstDiff = tabs.showGitDiffTabForActiveGroup()
        let secondDiff = tabs.showGitDiffTabForActiveGroup()

        XCTAssertEqual(firstDiff.id, secondDiff.id)
        XCTAssertEqual(tabs.tabs.compactMap { $0 as? GitDiffTab }.count, 1)
    }

    @MainActor
    func testDifferentTerminalTabsUseDifferentGroupsAndDiffTabs() {
        let tabs = TabCollection()
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))
        let firstDiff = tabs.showGitDiffTabForActiveGroup()
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-two"))
        let secondDiff = tabs.showGitDiffTabForActiveGroup()

        XCTAssertNotEqual(firstTerminal.groupState.id, secondTerminal.groupState.id)
        XCTAssertFalse(firstDiff.state === secondDiff.state)
        XCTAssertEqual(tabs.tabs.compactMap { $0 as? GitDiffTab }.count, 2)
    }

    @MainActor
    func testSingletonTabsKeepLastActiveContentGroup() {
        let tabs = TabCollection()
        let terminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))

        _ = tabs.showSettingsTab()
        XCTAssertEqual(tabs.activeTabGroup?.id, terminal.groupState.id)

        _ = tabs.showAboutTab()
        XCTAssertEqual(tabs.activeTabGroup?.id, terminal.groupState.id)
    }

    @MainActor
    func testClosingLastTabInGroupRemovesGroupState() async {
        let tabs = TabCollection()
        let terminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))

        let closed = await tabs.closeTab(id: terminal.id)

        XCTAssertTrue(closed)
        XCTAssertNil(tabs.tabGroups[terminal.groupState.id])
        XCTAssertNil(tabs.activeTabGroup)
    }

    @MainActor
    func testGroupShortcutIndexFollowsVisibleTabOrder() {
        let tabs = TabCollection()
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))
        _ = tabs.showGitDiffTabForActiveGroup()
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-two"))

        XCTAssertEqual(tabs.groupShortcutNumber(for: firstTerminal.groupState.id), 1)
        XCTAssertEqual(tabs.groupShortcutNumber(for: secondTerminal.groupState.id), 2)
    }

    @MainActor
    func testSelectingInactiveGroupShortcutActivatesFirstGroupTab() {
        let tabs = TabCollection()
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))
        _ = tabs.showGitDiffTabForActiveGroup()
        _ = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-two"))

        XCTAssertTrue(tabs.selectGroup(shortcutNumber: 1))

        XCTAssertEqual(tabs.activeTabID, firstTerminal.id)
        XCTAssertEqual(tabs.activeTabGroup?.id, firstTerminal.groupState.id)
    }

    @MainActor
    func testSelectingActiveGroupShortcutCyclesWithinGroupTabs() {
        let tabs = TabCollection()
        let terminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/terminal-one"))
        let diff = tabs.showGitDiffTabForActiveGroup()

        XCTAssertTrue(tabs.selectGroup(shortcutNumber: 1))
        XCTAssertEqual(tabs.activeTabID, terminal.id)

        XCTAssertTrue(tabs.selectGroup(shortcutNumber: 1))
        XCTAssertEqual(tabs.activeTabID, diff.id)
    }
}
