import AppKit
import XCTest
@testable import ma

final class TerminalSelectionSnippetCaptureTests: XCTestCase {
    @MainActor
    func testCommandShiftCStoresNonEmptyTerminalSelection() throws {
        let view = SearchAwareTerminalView()
        var storedBodies: [String] = []
        view.selectedTextProvider = { "selected terminal output" }
        view.onSnippetShortcut = { storedBodies.append($0) }

        XCTAssertTrue(view.performKeyEquivalent(with: try keyEvent(key: "c", keyCode: 8, modifiers: [.command, .shift])))
        XCTAssertEqual(storedBodies, ["selected terminal output"])
    }

    @MainActor
    func testCommandShiftCIgnoresBlankTerminalSelection() throws {
        let view = SearchAwareTerminalView()
        var storedBodies: [String] = []
        view.selectedTextProvider = { " \n\t " }
        view.onSnippetShortcut = { storedBodies.append($0) }

        XCTAssertTrue(view.performKeyEquivalent(with: try keyEvent(key: "c", keyCode: 8, modifiers: [.command, .shift])))
        XCTAssertTrue(storedBodies.isEmpty)
    }

    @MainActor
    func testCommandCDoesNotCreateSnippet() throws {
        let view = SearchAwareTerminalView()
        var storedBodies: [String] = []
        view.selectedTextProvider = { "copy only" }
        view.onSnippetShortcut = { storedBodies.append($0) }

        XCTAssertFalse(view.performKeyEquivalent(with: try keyEvent(key: "c", keyCode: 8, modifiers: [.command])))
        XCTAssertTrue(storedBodies.isEmpty)
    }

    private func keyEvent(key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: key.uppercased(),
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
