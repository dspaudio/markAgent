import AppKit
import XCTest
@testable import ma

final class PromptSnippetClipboardTests: XCTestCase {
    @MainActor
    func testCopyWritesExactStringToPasteboard() {
        let pasteboard = NSPasteboard.general
        let body = "hello agent"

        PromptSnippetClipboard.copy(body)

        XCTAssertEqual(pasteboard.string(forType: .string), body)
    }
}
