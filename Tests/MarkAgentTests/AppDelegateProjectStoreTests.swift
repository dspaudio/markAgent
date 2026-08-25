import AppKit
import Foundation
import XCTest
@testable import ma

final class AppDelegateProjectStoreTests: XCTestCase {
    @MainActor
    func testInitializerUsesInjectedProjectStore() {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProjectStore(defaults: defaults)
        let delegate = AppDelegate(projectStore: store)

        XCTAssertTrue(delegate.projectStore === store)
    }

    @MainActor
    func testOpenProjectCreatesActiveTerminalAndUpdatesDirectoryServices() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: rootDirectory)
        let expectedDirectory = projectDirectory.resolvingSymlinksInPath().standardizedFileURL
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))
        let delegate = AppDelegate(projectStore: store)
        let tabCount = delegate.tabs.tabs.count
        let terminalTabCount = delegate.tabs.tabs.compactMap { $0 as? TerminalTab }.count

        XCTAssertTrue(delegate.openProject(project))

        let terminalTab = try XCTUnwrap(delegate.tabs.activeTerminalTab)
        XCTAssertEqual(delegate.tabs.tabs.count, tabCount + 1)
        XCTAssertEqual(delegate.tabs.tabs.compactMap { $0 as? TerminalTab }.count, terminalTabCount + 1)
        XCTAssertEqual(terminalTab.workingDirectory, expectedDirectory)
        XCTAssertEqual(delegate.tabs.activeTabGroup?.workingDirectory, expectedDirectory)
        XCTAssertEqual(delegate.directoryScanner.currentDirectory, expectedDirectory)
        XCTAssertEqual(delegate.gitRepositoryStatus.currentDirectory, expectedDirectory)
    }

    @MainActor
    func testOpenProjectReusesExistingProjectTerminalWorkspace() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let firstDirectory = try createDirectory(named: "first", in: rootDirectory)
        let secondDirectory = try createDirectory(named: "second", in: rootDirectory)
        let store = ProjectStore(defaults: defaults)
        let firstProject = try XCTUnwrap(store.add(name: "First", directoryURL: firstDirectory))
        let secondProject = try XCTUnwrap(store.add(name: "Second", directoryURL: secondDirectory))
        let delegate = AppDelegate(projectStore: store)

        XCTAssertTrue(delegate.openProject(firstProject))
        let firstTerminal = try XCTUnwrap(delegate.tabs.activeTerminalTab)
        let firstGroupID = firstTerminal.groupState.id

        XCTAssertTrue(delegate.openProject(secondProject))
        let secondTerminal = try XCTUnwrap(delegate.tabs.activeTerminalTab)
        XCTAssertNotEqual(secondTerminal.id, firstTerminal.id)

        XCTAssertTrue(delegate.openProject(firstProject))

        XCTAssertEqual(delegate.tabs.activeTabID, firstTerminal.id)
        XCTAssertEqual(delegate.tabs.activeTabGroup?.id, firstGroupID)
        XCTAssertEqual(delegate.tabs.tabs.compactMap { $0 as? TerminalTab }.count, 1)
        XCTAssertEqual(delegate.tabs.allTabs.compactMap { $0 as? TerminalTab }.count, 2)
        XCTAssertEqual(
            delegate.directoryScanner.currentDirectory,
            firstDirectory.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    @MainActor
    func testOpenProjectRestoresProjectRightSidebarState() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let firstDirectory = try createDirectory(named: "first", in: rootDirectory)
        let secondDirectory = try createDirectory(named: "second", in: rootDirectory)
        let store = ProjectStore(defaults: defaults)
        let firstProject = try XCTUnwrap(store.add(name: "First", directoryURL: firstDirectory))
        let secondProject = try XCTUnwrap(store.add(name: "Second", directoryURL: secondDirectory))
        let delegate = AppDelegate(projectStore: store)

        XCTAssertTrue(delegate.openProject(firstProject))
        let firstGroup = try XCTUnwrap(delegate.tabs.activeTabGroup)
        firstGroup.selectRightUtility(.timeline)

        XCTAssertTrue(delegate.openProject(secondProject))
        let secondGroup = try XCTUnwrap(delegate.tabs.activeTabGroup)
        secondGroup.selectRightUtility(.fileBrowser)

        XCTAssertTrue(delegate.openProject(firstProject))

        XCTAssertTrue(delegate.tabs.activeTabGroup === firstGroup)
        XCTAssertTrue(firstGroup.rightUtilityRoute.isVisible)
        XCTAssertEqual(firstGroup.rightUtilityRoute.selectedTab, .timeline)
        XCTAssertTrue(secondGroup.rightUtilityRoute.isVisible)
        XCTAssertEqual(secondGroup.rightUtilityRoute.selectedTab, .fileBrowser)
    }

    @MainActor
    func testOpenProjectKeepsWorkspaceEmptyAfterTerminalCloses() async throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: rootDirectory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))
        let delegate = AppDelegate(projectStore: store)

        XCTAssertTrue(delegate.openProject(project))
        let originalTerminal = try XCTUnwrap(delegate.tabs.activeTerminalTab)
        let originalGroupID = originalTerminal.groupState.id

        let closed = await delegate.tabs.closeTab(id: originalTerminal.id)
        XCTAssertTrue(closed)
        XCTAssertTrue(delegate.openProject(project))

        XCTAssertNil(delegate.tabs.activeTerminalTab)
        XCTAssertNil(delegate.tabs.activeTabGroup)
        XCTAssertTrue(delegate.tabs.tabs.isEmpty)
        XCTAssertFalse(delegate.tabs.allTabs.contains { $0.id == originalTerminal.id })
        XCTAssertNotEqual(delegate.tabs.activeTabGroup?.id, originalGroupID)
    }

    @MainActor
    func testOpenProjectReplacesWorkspaceWhenStoredPathChanges() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let originalDirectory = try createDirectory(named: "original", in: rootDirectory)
        let replacementDirectory = try createDirectory(named: "replacement", in: rootDirectory)
        let expectedDirectory = replacementDirectory.resolvingSymlinksInPath().standardizedFileURL
        let store = ProjectStore(defaults: defaults)
        let originalProject = try XCTUnwrap(store.add(name: "Workspace", directoryURL: originalDirectory))
        let staleProject = originalProject
        let delegate = AppDelegate(projectStore: store)

        XCTAssertTrue(delegate.openProject(originalProject))
        let originalTerminal = try XCTUnwrap(delegate.tabs.activeTerminalTab)
        let updatedProject = try XCTUnwrap(
            store.update(originalProject, name: "Workspace", directoryURL: replacementDirectory)
        )

        XCTAssertTrue(delegate.openProject(staleProject))
        let replacementTerminal = try XCTUnwrap(delegate.tabs.activeTerminalTab)
        XCTAssertNotEqual(replacementTerminal.id, originalTerminal.id)
        XCTAssertEqual(replacementTerminal.workingDirectory, expectedDirectory)
        XCTAssertEqual(delegate.tabs.tabs.compactMap { $0 as? TerminalTab }.count, 2)

        XCTAssertTrue(delegate.openProject(updatedProject))
        XCTAssertEqual(delegate.tabs.activeTabID, replacementTerminal.id)
        XCTAssertEqual(delegate.tabs.tabs.compactMap { $0 as? TerminalTab }.count, 2)
    }

    @MainActor
    func testOpenProjectUsesCurrentDirectoryForStaleProjectValue() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let originalDirectory = try createDirectory(named: "original", in: rootDirectory)
        let currentDirectory = try createDirectory(named: "current", in: rootDirectory)
        let expectedDirectory = currentDirectory.resolvingSymlinksInPath().standardizedFileURL
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: originalDirectory))
        let staleProject = project
        _ = try XCTUnwrap(store.update(project, name: "Workspace", directoryURL: currentDirectory))
        let delegate = AppDelegate(projectStore: store)

        XCTAssertTrue(delegate.openProject(staleProject))

        XCTAssertEqual(delegate.tabs.activeTerminalTab?.workingDirectory, expectedDirectory)
        XCTAssertEqual(delegate.tabs.activeTabGroup?.workingDirectory, expectedDirectory)
        XCTAssertEqual(delegate.directoryScanner.currentDirectory, expectedDirectory)
        XCTAssertEqual(delegate.gitRepositoryStatus.currentDirectory, expectedDirectory)
    }

    @MainActor
    func testOpenProjectRejectsUnavailableDirectoryWithoutMutatingAppState() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: rootDirectory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))
        let delegate = AppDelegate(projectStore: store)
        try FileManager.default.removeItem(at: projectDirectory)
        let tabCount = delegate.tabs.tabs.count
        let scannerDirectory = delegate.directoryScanner.currentDirectory
        let gitDirectory = delegate.gitRepositoryStatus.currentDirectory

        XCTAssertFalse(delegate.openProject(project))

        XCTAssertEqual(delegate.tabs.tabs.count, tabCount)
        XCTAssertEqual(delegate.directoryScanner.currentDirectory, scannerDirectory)
        XCTAssertEqual(delegate.gitRepositoryStatus.currentDirectory, gitDirectory)
    }

    @MainActor
    func testOpenProjectRejectsDeletedProjectWithoutMutatingAppState() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: rootDirectory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))
        let delegate = AppDelegate(projectStore: store)
        store.delete(project)
        let tabCount = delegate.tabs.tabs.count
        let scannerDirectory = delegate.directoryScanner.currentDirectory
        let gitDirectory = delegate.gitRepositoryStatus.currentDirectory

        XCTAssertFalse(delegate.openProject(project))

        XCTAssertEqual(delegate.tabs.tabs.count, tabCount)
        XCTAssertEqual(delegate.directoryScanner.currentDirectory, scannerDirectory)
        XCTAssertEqual(delegate.gitRepositoryStatus.currentDirectory, gitDirectory)
    }

    @MainActor
    func testOpenProjectLeavesTerminalWindowTitleEmpty() throws {
        let suiteName = "AppDelegateProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: rootDirectory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))
        let delegate = AppDelegate(projectStore: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { delegate.window = nil }
        delegate.window = window

        XCTAssertTrue(delegate.openProject(project))
        XCTAssertEqual(window.title, "")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDelegateProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
