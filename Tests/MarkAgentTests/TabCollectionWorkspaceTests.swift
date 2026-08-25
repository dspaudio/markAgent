import XCTest
@testable import ma

final class TabCollectionWorkspaceTests: XCTestCase {
    @MainActor
    func testProjectWorkspacesExposeDisjointVisibleTabsAndRetainAllTabs() {
        let tabs = TabCollection()
        let firstWorkspace = TabWorkspaceID.project(UUID())
        let secondWorkspace = TabWorkspaceID.project(UUID())
        let firstDirectory = URL(fileURLWithPath: "/tmp/workspace-first")
        let secondDirectory = URL(fileURLWithPath: "/tmp/workspace-second")

        XCTAssertTrue(tabs.ensureWorkspace(firstWorkspace, rootDirectory: firstDirectory))
        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        let firstTerminal = tabs.createTerminalTab(workingDirectory: firstDirectory)
        let firstMarkdown = tabs.createMarkdownTab(fileURL: firstDirectory.appendingPathComponent("first.md"))

        XCTAssertTrue(tabs.ensureWorkspace(secondWorkspace, rootDirectory: secondDirectory))
        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: secondDirectory)

        XCTAssertEqual(tabs.tabs.map(\.id), [secondTerminal.id])
        XCTAssertEqual(Set(tabs.allTabs.map(\.id)), Set([firstTerminal.id, firstMarkdown.id, secondTerminal.id]))
        XCTAssertEqual(tabs.tabs(in: firstWorkspace).map(\.id), [firstTerminal.id, firstMarkdown.id])

        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        XCTAssertEqual(tabs.tabs.map(\.id), [firstTerminal.id, firstMarkdown.id])
        XCTAssertFalse(tabs.tabs.contains { $0.id == secondTerminal.id })
    }

    @MainActor
    func testWorkspaceSwitchRestoresActiveTabGroupAndRightUtilityState() {
        let tabs = TabCollection()
        let firstWorkspace = TabWorkspaceID.project(UUID())
        let secondWorkspace = TabWorkspaceID.project(UUID())
        let firstDirectory = URL(fileURLWithPath: "/tmp/workspace-first")
        let secondDirectory = URL(fileURLWithPath: "/tmp/workspace-second")

        XCTAssertTrue(tabs.ensureWorkspace(firstWorkspace, rootDirectory: firstDirectory))
        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        let firstTerminal = tabs.createTerminalTab(workingDirectory: firstDirectory)
        let firstMarkdown = tabs.createMarkdownTab(fileURL: firstDirectory.appendingPathComponent("first.md"))
        firstTerminal.groupState.selectRightUtility(.timeline)

        XCTAssertTrue(tabs.ensureWorkspace(secondWorkspace, rootDirectory: secondDirectory))
        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: secondDirectory)
        secondTerminal.groupState.selectRightUtility(.fileBrowser)

        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))

        XCTAssertEqual(tabs.activeTabID, firstMarkdown.id)
        XCTAssertTrue(tabs.activeTabGroup === firstTerminal.groupState)
        XCTAssertEqual(tabs.activeTabGroup?.rightUtilityRoute.selectedTab, .timeline)

        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        XCTAssertEqual(tabs.activeTabID, secondTerminal.id)
        XCTAssertTrue(tabs.activeTabGroup === secondTerminal.groupState)
        XCTAssertEqual(tabs.activeTabGroup?.rightUtilityRoute.selectedTab, .fileBrowser)
    }

    @MainActor
    func testClosingActiveTabNeverSelectsAnotherWorkspace() async {
        let tabs = TabCollection()
        let firstWorkspace = TabWorkspaceID.project(UUID())
        let secondWorkspace = TabWorkspaceID.project(UUID())

        XCTAssertTrue(tabs.ensureWorkspace(firstWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/first")))
        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/first-one"))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/first-two"))

        XCTAssertTrue(tabs.ensureWorkspace(secondWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/second")))
        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        let otherWorkspaceTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/second"))

        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        tabs.selectTab(id: secondTerminal.id)
        let closed = await tabs.closeActiveTab()
        XCTAssertTrue(closed)

        XCTAssertEqual(tabs.activeWorkspaceID, firstWorkspace)
        XCTAssertEqual(tabs.activeTabID, firstTerminal.id)
        XCTAssertNotEqual(tabs.activeTabID, otherWorkspaceTerminal.id)
    }

    @MainActor
    func testReorderAndShortcutsOperateWithinActiveWorkspace() {
        let tabs = TabCollection()
        let firstWorkspace = TabWorkspaceID.project(UUID())
        let secondWorkspace = TabWorkspaceID.project(UUID())

        XCTAssertTrue(tabs.ensureWorkspace(firstWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/first")))
        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/first-one"))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/first-two"))

        XCTAssertTrue(tabs.ensureWorkspace(secondWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/second")))
        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        let otherWorkspaceTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/second"))

        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        tabs.moveTab(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        XCTAssertEqual(tabs.tabs.map(\.id), [secondTerminal.id, firstTerminal.id])
        XCTAssertEqual(tabs.tabs(in: secondWorkspace).map(\.id), [otherWorkspaceTerminal.id])

        tabs.selectTab(at: 0)
        XCTAssertEqual(tabs.activeTabID, secondTerminal.id)
        XCTAssertTrue(tabs.selectGroup(shortcutNumber: 2))
        XCTAssertEqual(tabs.activeTabID, firstTerminal.id)
    }

    @MainActor
    func testSwitchingBetweenEmptyWorkspacesChangesVisibleProjection() {
        let tabs = TabCollection()
        let firstWorkspace = TabWorkspaceID.project(UUID())
        let secondWorkspace = TabWorkspaceID.project(UUID())

        XCTAssertTrue(tabs.ensureWorkspace(firstWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/first")))
        XCTAssertTrue(tabs.ensureWorkspace(secondWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/second")))

        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        XCTAssertEqual(tabs.activeWorkspaceID, firstWorkspace)
        XCTAssertTrue(tabs.tabs.isEmpty)

        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        XCTAssertEqual(tabs.activeWorkspaceID, secondWorkspace)
        XCTAssertTrue(tabs.tabs.isEmpty)
    }

    @MainActor
    func testRemovingActiveProjectWorkspaceMigratesTabsToUnscoped() {
        let tabs = TabCollection()
        let workspaceID = TabWorkspaceID.project(UUID())
        let directory = URL(fileURLWithPath: "/tmp/project")

        XCTAssertTrue(tabs.ensureWorkspace(workspaceID, rootDirectory: directory))
        XCTAssertTrue(tabs.selectWorkspace(workspaceID))
        let terminal = tabs.createTerminalTab(workingDirectory: directory)
        let markdown = tabs.createMarkdownTab(fileURL: directory.appendingPathComponent("note.md"))

        XCTAssertTrue(tabs.removeWorkspace(workspaceID))

        XCTAssertEqual(tabs.activeWorkspaceID, .unscoped)
        XCTAssertEqual(tabs.tabs.map(\.id), [terminal.id, markdown.id])
        XCTAssertEqual(tabs.activeTabID, markdown.id)
        XCTAssertTrue(tabs.activeTabGroup === terminal.groupState)
    }

    @MainActor
    func testRemovingInactiveProjectWorkspaceDoesNotChangeActiveProject() {
        let tabs = TabCollection()
        let firstWorkspace = TabWorkspaceID.project(UUID())
        let secondWorkspace = TabWorkspaceID.project(UUID())

        XCTAssertTrue(tabs.ensureWorkspace(firstWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/first")))
        XCTAssertTrue(tabs.selectWorkspace(firstWorkspace))
        let firstTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/first"))

        XCTAssertTrue(tabs.ensureWorkspace(secondWorkspace, rootDirectory: URL(fileURLWithPath: "/tmp/second")))
        XCTAssertTrue(tabs.selectWorkspace(secondWorkspace))
        let secondTerminal = tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/second"))

        XCTAssertTrue(tabs.removeWorkspace(firstWorkspace))

        XCTAssertEqual(tabs.activeWorkspaceID, secondWorkspace)
        XCTAssertEqual(tabs.activeTabID, secondTerminal.id)
        XCTAssertEqual(tabs.tabs.map(\.id), [secondTerminal.id])
        XCTAssertTrue(tabs.tabs(in: .unscoped).contains { $0.id == firstTerminal.id })
    }
}
