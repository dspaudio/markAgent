import XCTest
@testable import ma

final class TerminalKeybindRoutingTests: XCTestCase {
    func testCommandShiftCIsReservedForSnippetShortcut() {
        XCTAssertTrue(TerminalKeybindRouting.isSnippetShortcut(key: "c", modifiers: [.command, .shift]))
        XCTAssertTrue(TerminalKeybindRouting.shouldSkipConfiguredTerminalKeybind(key: "c", modifiers: [.command, .shift]))
    }

    func testSearchShortcutsStillSkipConfiguredTerminalKeybinds() {
        XCTAssertTrue(TerminalKeybindRouting.shouldSkipConfiguredTerminalKeybind(key: "f", modifiers: [.command, .shift]))
        XCTAssertTrue(TerminalKeybindRouting.shouldSkipConfiguredTerminalKeybind(key: "g", modifiers: [.command, .shift]))
    }

    func testCommandCMayUseExistingTerminalCopyFallback() {
        XCTAssertFalse(TerminalKeybindRouting.shouldSkipConfiguredTerminalKeybind(key: "c", modifiers: [.command]))
    }
}
