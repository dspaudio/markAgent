import XCTest
@testable import ma

final class EditorPerformanceTests: XCTestCase {
    func testLineIndexReturnsCursorPositionInLargeDocument() {
        let text = (0..<120_000).map { "line \($0)" }.joined(separator: "\n")
        let index = EditorLineIndex(text: text)
        let location = (text as NSString).length

        let position = index.cursorPosition(for: location)

        XCTAssertEqual(position.line, 120_000)
        XCTAssertEqual(position.column, "line 119999".count + 1)
    }

    func testLineIndexClampsInvalidLocations() {
        let index = EditorLineIndex(text: "first\nsecond")

        XCTAssertEqual(index.cursorPosition(for: -100), EditorCursorPosition(line: 1, column: 1))
        XCTAssertEqual(index.cursorPosition(for: 10_000), EditorCursorPosition(line: 2, column: 7))
    }

    func testLineIndexHandlesUTF16Locations() {
        let text = "😀\nabc"
        let index = EditorLineIndex(text: text)

        XCTAssertEqual(index.cursorPosition(for: 2), EditorCursorPosition(line: 1, column: 3))
        XCTAssertEqual(index.cursorPosition(for: 3), EditorCursorPosition(line: 2, column: 1))
    }

    func testRawStylePolicyDoesNotRestyleLocalEdits() {
        var policy = EditorStylePolicy(mode: .raw, colorSignature: "a")

        XCTAssertFalse(policy.shouldStyleLocalEdit())
        XCTAssertFalse(policy.shouldApplyFullStyle(mode: .raw, colorSignature: "a"))
        XCTAssertTrue(policy.shouldApplyFullStyle(mode: .raw, colorSignature: "b"))
    }

    func testRenderedStylePolicyRestylesLocalEdits() {
        let policy = EditorStylePolicy(mode: .renderedMarkdown)

        XCTAssertTrue(policy.shouldStyleLocalEdit())
    }
}

