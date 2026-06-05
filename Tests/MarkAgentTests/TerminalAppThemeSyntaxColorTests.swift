import XCTest
@testable import ma

final class TerminalAppThemeSyntaxColorTests: XCTestCase {
    func testAppColorsExposeSyntaxColorsFromGhosttyPalette() {
        let theme = TerminalColorTheme(
            name: "Syntax Test",
            background: "111111",
            foreground: "eeeeee",
            cursorColor: nil,
            selectionBackground: nil,
            selectionForeground: nil,
            palette: [
                1: "aa0000",
                2: "00aa00",
                3: "aaaa00",
                4: "0000aa",
                5: "aa00aa",
                6: "00aaaa",
            ]
        )

        let colors = theme.appColors()

        XCTAssertEqual(colors?.syntaxRed.hexRGB, "aa0000")
        XCTAssertEqual(colors?.syntaxGreen.hexRGB, "00aa00")
        XCTAssertEqual(colors?.syntaxYellow.hexRGB, "aaaa00")
        XCTAssertEqual(colors?.syntaxBlue.hexRGB, "0000aa")
        XCTAssertEqual(colors?.syntaxMagenta.hexRGB, "aa00aa")
        XCTAssertEqual(colors?.syntaxCyan.hexRGB, "00aaaa")
    }

    func testPreviewHighlightCSSUsesThemeSyntaxPalette() throws {
        let theme = TerminalColorTheme(
            name: "Preview Syntax Test",
            background: "101820",
            foreground: "f0f4f8",
            cursorColor: nil,
            selectionBackground: nil,
            selectionForeground: nil,
            palette: [
                1: "ff5c57",
                2: "5af78e",
                3: "f3f99d",
                4: "57c7ff",
                5: "ff6ac1",
                6: "9aedfe",
            ]
        )

        let colors = try XCTUnwrap(theme.appColors())
        let css = colors.highlightCSS

        XCTAssertTrue(css.contains(".hljs{color:#f0f4f8}"))
        XCTAssertTrue(css.contains(".hljs-addition,.hljs-string,.hljs-symbol{color:#5af78e}"))
        XCTAssertTrue(css.contains(".hljs-attr,.hljs-attribute,.hljs-literal,.hljs-number,.hljs-variable{color:#f3f99d}"))
        XCTAssertTrue(css.contains(".hljs-keyword,.hljs-selector-tag,.hljs-template-tag,.hljs-type{color:#ff6ac1}"))
        XCTAssertTrue(css.contains(".hljs-name,.hljs-section,.hljs-title,.hljs-title.function_{color:#57c7ff}"))
    }
}

private extension NSColor {
    var hexRGB: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "%02x%02x%02x",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
