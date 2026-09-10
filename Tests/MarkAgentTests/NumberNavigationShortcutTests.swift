import AppKit
import XCTest
@testable import ma

final class NumberNavigationShortcutTests: XCTestCase {
    @MainActor
    func testNumberKeysSeparateWorkspaceAndTabShortcutsIncludingShiftedSymbols() throws {
        let keys: [(UInt16, String)] = [
            (18, "!"), (19, "@"), (20, "#"), (21, "$"), (23, "%"),
            (22, "^"), (26, "&"), (28, "*"), (25, "("), (29, ")"),
        ]

        for (index, key) in keys.enumerated() {
            let number = index + 1
            let workspaceEvent = try keyEvent(keyCode: key.0, characters: String(number % 10), modifiers: .command)
            let tabEvent = try keyEvent(keyCode: key.0, characters: key.1, modifiers: [.command, .shift])

            XCTAssertEqual(NumberNavigationShortcut(event: workspaceEvent), .workspace(number))
            XCTAssertEqual(NumberNavigationShortcut(event: tabEvent), .tab(number))
        }
    }

    @MainActor
    func testNumericKeypadUsesTheSameNavigationMapping() throws {
        let keyCodes: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92, 82]
        for (index, keyCode) in keyCodes.enumerated() {
            let number = index + 1
            let event = try keyEvent(keyCode: keyCode, characters: String(number % 10), modifiers: [.command, .numericPad])
            XCTAssertEqual(NumberNavigationShortcut(event: event), .workspace(number))
        }
    }

    @MainActor
    func testNavigationIgnoresCapsLockAndRejectsOtherModifiersAndKeys() throws {
        let capsLockEvent = try keyEvent(keyCode: 18, characters: "!", modifiers: [.command, .shift, .capsLock])
        XCTAssertEqual(NumberNavigationShortcut(event: capsLockEvent), .tab(1))

        for modifiers: NSEvent.ModifierFlags in [[], .shift, [.command, .option], [.command, .control], [.command, .shift, .option]] {
            let event = try keyEvent(keyCode: 18, characters: "1", modifiers: modifiers)
            XCTAssertNil(NumberNavigationShortcut(event: event))
        }

        let letterEvent = try keyEvent(keyCode: 3, characters: "f", modifiers: [.command, .shift])
        XCTAssertNil(NumberNavigationShortcut(event: letterEvent))
    }

    @MainActor
    func testWorkspaceShortcutsFollowCurrentProjectOrderAndRestoreDefaultWorkspace() throws {
        try withDelegate(projectCount: 2) { delegate, store, _ in
            let defaultTab = delegate.tabs.createMarkdownTab(fileURL: nil)
            let first = store.projects[0]
            let second = store.projects[1]

            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 19, characters: "2")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(first.id))
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 20, characters: "3")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(second.id))

            XCTAssertTrue(store.moveProjects(fromOffsets: IndexSet(integer: 1), toOffset: 0))
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 19, characters: "2")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(second.id))
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 20, characters: "3")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(first.id))

            store.delete(second)
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 19, characters: "2")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(first.id))
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 18, characters: "1")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .unscoped)
            XCTAssertEqual(delegate.tabs.activeTabID, defaultTab.id)
        }
    }

    @MainActor
    func testCommandZeroSelectsNinthProjectAndShiftZeroSelectsTenthTab() throws {
        try withDelegate(projectCount: 9) { delegate, store, _ in
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 29, characters: "0")))
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(store.projects[8].id))

            for _ in 0..<9 {
                delegate.tabs.createMarkdownTab(fileURL: nil)
            }
            let tenthTab = try XCTUnwrap(delegate.tabs.tabs.last)
            delegate.tabs.selectTab(at: 0)

            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 29, characters: ")", modifiers: [.command, .shift])))
            XCTAssertEqual(delegate.tabs.activeTabID, tenthTab.id)
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(store.projects[8].id))
        }
    }

    @MainActor
    func testShiftNumberKeepsTabGroupSelectionAndCyclingWithinActiveWorkspace() throws {
        try withDelegate(projectCount: 1) { delegate, store, directory in
            let defaultTab = delegate.tabs.createMarkdownTab(fileURL: nil)
            XCTAssertTrue(delegate.openProject(store.projects[0]))
            let firstTerminal = try XCTUnwrap(delegate.tabs.activeTerminalTab)
            let child = delegate.tabs.createMarkdownTab(fileURL: nil)
            let secondTerminal = delegate.tabs.createTerminalTab(workingDirectory: directory)
            let firstGroupEvent = try keyEvent(keyCode: 18, characters: "!", modifiers: [.command, .shift])

            XCTAssertTrue(delegate.handleNavigationKeybind(firstGroupEvent))
            XCTAssertEqual(delegate.tabs.activeTabID, firstTerminal.id)
            XCTAssertTrue(delegate.handleNavigationKeybind(firstGroupEvent))
            XCTAssertEqual(delegate.tabs.activeTabID, child.id)
            XCTAssertTrue(delegate.handleNavigationKeybind(firstGroupEvent))
            XCTAssertEqual(delegate.tabs.activeTabID, firstTerminal.id)
            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 19, characters: "@", modifiers: [.command, .shift])))
            XCTAssertEqual(delegate.tabs.activeTabID, secondTerminal.id)
            XCTAssertEqual(delegate.tabs.activeWorkspaceID, .project(store.projects[0].id))

            XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 18, characters: "1")))
            XCTAssertEqual(delegate.tabs.activeTabID, defaultTab.id)
        }
    }

    @MainActor
    func testMissingShortcutTargetsAreConsumedWithoutChangingSelection() throws {
        try withDelegate(projectCount: 0) { delegate, _, _ in
            let tab = delegate.tabs.createMarkdownTab(fileURL: nil)
            for modifiers: NSEvent.ModifierFlags in [.command, [.command, .shift]] {
                XCTAssertTrue(delegate.handleNavigationKeybind(try keyEvent(keyCode: 29, characters: "0", modifiers: modifiers)))
                XCTAssertEqual(delegate.tabs.activeTabID, tab.id)
                XCTAssertEqual(delegate.tabs.activeWorkspaceID, .unscoped)
            }
        }
    }

    @MainActor
    func testWindowRoutesNavigationBeforeConfiguredTerminalBindings() throws {
        let window = MarkAgentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var navigationCount = 0
        var terminalCount = 0
        window.navigationKeybindHandler = { event in
            guard NumberNavigationShortcut(event: event) != nil else { return false }
            navigationCount += 1
            return true
        }
        window.terminalKeybindHandler = { _ in
            terminalCount += 1
            return true
        }

        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(keyCode: 18, characters: "1")))
        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(keyCode: 19, characters: "@", modifiers: [.command, .shift])))
        XCTAssertEqual(navigationCount, 2)
        XCTAssertEqual(terminalCount, 0)
        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(keyCode: 0, characters: "a")))
        XCTAssertEqual(terminalCount, 1)
    }

    @MainActor
    func testWorkspaceMenuValidationReflectsReorderRenameAndDeletion() throws {
        try withDelegate(projectCount: 2) { delegate, store, _ in
            let item = NSMenuItem(title: "", action: NSSelectorFromString("gotoWorkspace:"), keyEquivalent: "2")
            item.tag = 2
            XCTAssertTrue(delegate.validateMenuItem(item))
            XCTAssertEqual(item.title, store.projects[0].name)

            XCTAssertTrue(store.moveProjects(fromOffsets: IndexSet(integer: 1), toOffset: 0))
            let first = store.projects[0]
            _ = try XCTUnwrap(store.update(first, name: "Renamed", directoryURL: first.directoryURL))
            XCTAssertTrue(delegate.validateMenuItem(item))
            XCTAssertEqual(item.title, "Renamed")

            item.tag = 3
            store.delete(store.projects[1])
            XCTAssertFalse(delegate.validateMenuItem(item))
        }
    }

    @MainActor
    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @MainActor
    private func withDelegate(
        projectCount: Int,
        body: (AppDelegate, ProjectStore, URL) throws -> Void
    ) throws {
        let suiteName = "NumberNavigationShortcutTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ProjectStore(defaults: defaults)
        for index in 0..<projectCount {
            let projectDirectory = directory.appendingPathComponent("project-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            _ = try XCTUnwrap(store.add(name: "Project \(index)", directoryURL: projectDirectory))
        }
        let delegate = AppDelegate(projectStore: store)
        try body(delegate, store, directory)
    }
}
