import AppKit
import XCTest
@testable import ma

final class TerminalSelectionPasteboardReaderTests: XCTestCase {
    @MainActor
    func testReturnsSelectedTextAndRestoresPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard", forType: .string)

        let selectedText = TerminalSelectionPasteboardReader.readSelectedText(pasteboard: pasteboard) {
            pasteboard.clearContents()
            pasteboard.setString("selected terminal text", forType: .string)
            return true
        }

        XCTAssertEqual(selectedText, "selected terminal text")
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard")
    }

    @MainActor
    func testReturnsNilWhenCopyFailsAndRestoresPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard", forType: .string)

        let selectedText = TerminalSelectionPasteboardReader.readSelectedText(pasteboard: pasteboard) {
            pasteboard.clearContents()
            pasteboard.setString("transient", forType: .string)
            return false
        }

        XCTAssertNil(selectedText)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard")
    }

    @MainActor
    func testReturnsNilWhenCopyActionDoesNotReplacePasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard", forType: .string)

        let selectedText = TerminalSelectionPasteboardReader.readSelectedText(pasteboard: pasteboard) {
            true
        }

        XCTAssertNil(selectedText)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard")
    }
}
