import XCTest
@testable import ma

final class RawCodeSyntaxRuleTests: XCTestCase {
    func testPHPPatternsMatchKeywordsCommentsStringsAndNumbers() {
        let source = """
        <?php
        // comment
        final class User {
            public function name(): string {
                return "mark-agent-42";
            }
        }
        """

        assertPattern(.keyword, language: .php, matches: ["final", "class", "public", "function", "return"], in: source)
        assertPattern(.comment, language: .php, matches: ["// comment"], in: source)
        assertPattern(.string, language: .php, matches: ["\"mark-agent-42\""], in: source)
        assertPattern(.number, language: .php, matches: ["42"], in: source)
    }

    func testJavaScriptPatternsMatchKeywordsCommentsStringsAndNumbers() {
        let source = """
        // comment
        export function run() {
            const value = "mark-agent";
            return value.length + 42;
        }
        """

        assertPattern(.keyword, language: .javascript, matches: ["function", "const", "return"], in: source)
        assertPattern(.comment, language: .javascript, matches: ["// comment"], in: source)
        assertPattern(.string, language: .javascript, matches: ["\"mark-agent\""], in: source)
        assertPattern(.number, language: .javascript, matches: ["42"], in: source)
    }

    func testTypeScriptPatternsMatchKeywordsCommentsStringsAndNumbers() {
        let source = """
        interface User {
            name: string;
        }

        export function render(user: User): string {
            return `count-${42}`;
        }
        """

        assertPattern(.keyword, language: .typescript, matches: ["interface", "function", "return"], in: source)
        assertPattern(.string, language: .typescript, matches: ["`count-${42}`"], in: source)
        assertPattern(.number, language: .typescript, matches: ["42"], in: source)
    }

    private func assertPattern(
        _ token: RawCodeSyntaxToken,
        language: CodeHighlightLanguage,
        matches expectedMatches: [String],
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pattern = RawCodeSyntaxRules.pattern(for: token, language: language)
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            XCTFail("Invalid regex for \(token) / \(language): \(error)", file: file, line: line)
            return
        }
        let range = NSRange(location: 0, length: (source as NSString).length)
        let matches = regex
            .matches(in: source, range: range)
            .map { (source as NSString).substring(with: $0.range) }

        for expectedMatch in expectedMatches {
            XCTAssertTrue(
                matches.contains(expectedMatch),
                "Expected \(token) pattern for \(language) to match \(expectedMatch), got \(matches)",
                file: file,
                line: line
            )
        }
    }
}
