import AppKit
import XCTest
@testable import ma

final class PromptSnippetClipboardTests: XCTestCase {
    @MainActor
    func testCopyWritesExactStringToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkAgentTests-\(UUID().uuidString)"))
        let body = "hello agent"

        PromptSnippetClipboard.copy(body, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), body)
    }
}
