import XCTest
@testable import ma

final class CodeHighlightLanguageTests: XCTestCase {
    func testRecognizesRequestedCodeFileExtensions() {
        let cases: [(String, CodeHighlightLanguage)] = [
            ("Component.tsx", .tsx),
            ("index.ts", .typescript),
            ("script.js", .javascript),
            ("script.jsx", .jsx),
            ("module.mjs", .javascript),
            ("module.cjs", .javascript),
            ("types.mts", .typescript),
            ("types.cts", .typescript),
            ("main.swift", .swift),
            ("module.php", .php),
            ("bridge.h", .objectiveC),
            ("legacy.o", .objectiveC),
            ("tool.py", .python),
            ("styles.css", .css),
            ("styles.scss", .scss),
            ("styles.sass", .sass),
            ("styles.less", .less),
            ("index.html", .html),
            ("component.vue", .vue),
            ("component.svelte", .svelte),
            ("page.astro", .astro),
            ("post.mdx", .mdx),
            ("feed.xml", .xml),
            (".env", .env),
            ("docker.env", .env),
            ("compose.yaml", .yaml),
            ("settings.yml", .yaml),
            ("Cargo.toml", .toml),
            ("package.json", .json),
            ("tsconfig.jsonc", .jsonc),
            ("events.jsonl", .jsonl),
            ("Dockerfile", .dockerfile),
            ("Makefile", .makefile),
            ("query.sql", .sql),
            ("main.rs", .rust),
            ("main.go", .go),
            ("Main.java", .java),
            ("main.kt", .kotlin),
            ("schema.graphql", .graphql),
            ("schema.proto", .protobuf),
            ("shell.sh", .shell),
            ("script.zsh", .shell),
            ("flake.nix", .nix),
            ("patch.diff", .diff),
            ("Gemfile", .ruby),
        ]

        for (fileName, expectedLanguage) in cases {
            XCTAssertEqual(CodeHighlightLanguage(fileURL: URL(fileURLWithPath: fileName)), expectedLanguage)
        }
    }

    func testIgnoresUnsupportedExtensions() {
        XCTAssertNil(CodeHighlightLanguage(fileURL: URL(fileURLWithPath: "notes.md")))
        XCTAssertNil(CodeHighlightLanguage(fileURL: URL(fileURLWithPath: "image.png")))
        XCTAssertNil(CodeHighlightLanguage(fileURL: URL(fileURLWithPath: "README")))
        XCTAssertNil(CodeHighlightLanguage(fileURL: nil))
    }
}
