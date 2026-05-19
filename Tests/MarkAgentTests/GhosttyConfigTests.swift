import XCTest
@testable import ma

final class GhosttyConfigTests: XCTestCase {
    func testParseFontSizeUsesLastActiveValue() {
        let contents = """
        font-size = 12
        # font-size = 20
        font-size = 15.5
        """

        XCTAssertEqual(GhosttyConfig.parseFontSize(from: contents), 15.5)
    }

    func testParseFontSizeIgnoresInlineCommentLikeGhostty() {
        let contents = """
        font-size = 16 # not a Ghostty comment
        font-size = 17
        """

        XCTAssertEqual(GhosttyConfig.parseFontSize(from: contents), 17)
    }

    func testUserConfigPrefersXdgConfigPath() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhosttyConfigTests-\(UUID().uuidString)")
        let xdgConfig = home.appendingPathComponent(".config/ghostty/config")
        let applicationSupportConfig = home
            .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config")
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(
            at: xdgConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupportConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "font-size = 14".write(to: xdgConfig, atomically: true, encoding: .utf8)
        try "font-size = 18".write(to: applicationSupportConfig, atomically: true, encoding: .utf8)

        let config = GhosttyConfig.userConfig(homeDirectory: home)

        XCTAssertEqual(config?.url.path, xdgConfig.path)
        XCTAssertEqual(config?.fontSize, 14)
    }

    func testUserConfigPreservesFontFamilyLines() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhosttyConfigTests-\(UUID().uuidString)")
        let xdgConfig = home.appendingPathComponent(".config/ghostty/config")
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(
            at: xdgConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        font-family = "JetBrains Mono"
        font-family = "Noto Sans CJK KR"
        font-size = 16
        """.write(to: xdgConfig, atomically: true, encoding: .utf8)

        let config = GhosttyConfig.userConfig(homeDirectory: home)

        XCTAssertEqual(config?.fontSize, 16)
        XCTAssertEqual(config?.fontFamilies, ["\"JetBrains Mono\"", "\"Noto Sans CJK KR\""])
        XCTAssertTrue(config?.contents.contains("font-family = \"JetBrains Mono\"") == true)
        XCTAssertTrue(config?.contents.contains("font-family = \"Noto Sans CJK KR\"") == true)
    }

    func testParseFontFamiliesPreservesOrderAndQuotes() {
        let contents = """
        font-family = "JetBrains Mono"
        font-size = 16
        # font-family = "Ignored"
        font-family = "Noto Sans CJK KR"
        """

        XCTAssertEqual(
            GhosttyConfig.parseFontFamilies(from: contents),
            ["\"JetBrains Mono\"", "\"Noto Sans CJK KR\""]
        )
    }
}
