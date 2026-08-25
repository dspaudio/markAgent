import AppKit
import XCTest
@testable import ma

final class TerminalSnippetSelectionSaverTests: XCTestCase {
    @MainActor
    func testSavesSelectedTextAndConsumesShortcut() {
        let suiteName = "TerminalSnippetSelectionSaverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pasteboard = NSPasteboard.withUniqueName()
        let store = PromptSnippetStore(defaults: defaults)
        var didSave = false

        let consumed = TerminalSnippetSelectionSaver.saveSelection(
            to: store,
            pasteboard: pasteboard,
            copySelectionToPasteboard: {
                pasteboard.clearContents()
                pasteboard.setString("selected terminal text", forType: .string)
                return true
            },
            onSaved: { didSave = true }
        )

        XCTAssertTrue(consumed)
        XCTAssertTrue(didSave)
        XCTAssertEqual(store.snippets.map(\.body), ["selected terminal text"])
    }

    @MainActor
    func testSuccessfulSaveCanOpenSnippetsSidebar() {
        let suiteName = "TerminalSnippetSelectionSaverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pasteboard = NSPasteboard.withUniqueName()
        let store = PromptSnippetStore(defaults: defaults)
        let group = TabGroupState()
        group.rightUtilityRoute.selectedTab = .gitHistory

        let consumed = TerminalSnippetSelectionSaver.saveSelection(
            to: store,
            pasteboard: pasteboard,
            copySelectionToPasteboard: {
                pasteboard.clearContents()
                pasteboard.setString("selected terminal text", forType: .string)
                return true
            },
            onSaved: {
                group.showSnippetsSidebar()
            }
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(store.snippets.map(\.body), ["selected terminal text"])
        XCTAssertTrue(group.rightUtilityRoute.isVisible)
        XCTAssertEqual(group.rightUtilityRoute.selectedTab, .snippets)
    }

    @MainActor
    func testConsumesShortcutWithoutSavingBlankSelection() {
        let suiteName = "TerminalSnippetSelectionSaverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pasteboard = NSPasteboard.withUniqueName()
        let store = PromptSnippetStore(defaults: defaults)
        var didSave = false

        let consumed = TerminalSnippetSelectionSaver.saveSelection(
            to: store,
            pasteboard: pasteboard,
            copySelectionToPasteboard: {
                pasteboard.clearContents()
                pasteboard.setString(" \n\t ", forType: .string)
                return true
            },
            onSaved: { didSave = true }
        )

        XCTAssertTrue(consumed)
        XCTAssertFalse(didSave)
        XCTAssertTrue(store.snippets.isEmpty)
    }
}
