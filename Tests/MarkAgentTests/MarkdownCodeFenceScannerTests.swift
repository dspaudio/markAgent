import XCTest
@testable import ma

final class MarkdownCodeFenceScannerTests: XCTestCase {
    func testFindsClosedFenceWithLanguageAndCodeRange() {
        let text = """
        Intro
        ```swift
        let value = 42
        ```
        Outro
        """

        let fences = MarkdownCodeFenceScanner.fences(in: text)

        XCTAssertEqual(fences.count, 1)
        guard let fence = fences.first else { return }
        XCTAssertEqual(fence.language, "swift")
        XCTAssertEqual((text as NSString).substring(with: fence.codeRange), "let value = 42\n")
        XCTAssertEqual((text as NSString).substring(with: fence.openingRange), "```swift")
        XCTAssertEqual((text as NSString).substring(with: fence.closingRange!), "```")
    }

    func testFindsUnclosedFenceToEndOfDocument() {
        let text = """
        ```js
        const value = true
        """

        let fences = MarkdownCodeFenceScanner.fences(in: text)

        XCTAssertEqual(fences.count, 1)
        guard let fence = fences.first else { return }
        XCTAssertEqual(fence.language, "js")
        XCTAssertNil(fence.closingRange)
        XCTAssertEqual((text as NSString).substring(with: fence.codeRange), "const value = true")
    }

    func testIgnoresIndentedFenceLikeTextInsideCodeContent() {
        let text = """
        ```python
        print("start")
          ```
        print("still code")
        ```
        """

        let fences = MarkdownCodeFenceScanner.fences(in: text)

        XCTAssertEqual(fences.count, 1)
        guard let fence = fences.first else { return }
        XCTAssertEqual((text as NSString).substring(with: fence.codeRange), "print(\"start\")\n  ```\nprint(\"still code\")\n")
    }
}
