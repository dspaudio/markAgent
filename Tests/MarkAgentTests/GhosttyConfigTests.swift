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

    func testUserConfigAddsDefaultKoreanFallbackFontWhenMissing() throws {
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
        font-size = 16
        """.write(to: xdgConfig, atomically: true, encoding: .utf8)

        let config = GhosttyConfig.userConfig(homeDirectory: home)

        XCTAssertEqual(config?.fontFamilies, ["\"JetBrains Mono\"", "\"Apple SD Gothic Neo\""])
    }

    func testResolvedAppThemeUsesDarkModernWhenConfigFileIsMissing() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhosttyConfigTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        let theme = GhosttyConfig.resolvedAppTheme(homeDirectory: home)

        XCTAssertEqual(theme?.theme(for: .dark)?.name, "Dark Modern")
        XCTAssertEqual(theme?.preferredColorScheme, .dark)
    }

    func testResolvedAppThemeUsesConfiguredNamedTheme() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhosttyConfigTests-\(UUID().uuidString)")
        let configURL = home.appendingPathComponent(".config/ghostty/config")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "theme = Catppuccin Latte\n".write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )

        let theme = GhosttyConfig.resolvedAppTheme(homeDirectory: home)

        XCTAssertEqual(theme?.theme(for: .light)?.name, "Catppuccin Latte")
        XCTAssertEqual(theme?.preferredColorScheme, .light)
    }

    func testPreferencesReadThemeAndFontChoices() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhosttyConfigTests-\(UUID().uuidString)")
        let xdgConfig = home.appendingPathComponent(".config/ghostty/config")
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(
            at: xdgConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        theme = Dracula
        font-family = "JetBrains Mono"
        font-family = "Noto Sans CJK KR"
        font-size = 16
        """.write(to: xdgConfig, atomically: true, encoding: .utf8)

        let preferences = GhosttyConfig.preferences(homeDirectory: home)

        XCTAssertEqual(preferences.configURL.path, xdgConfig.path)
        XCTAssertEqual(preferences.themeName, "Dracula")
        XCTAssertEqual(preferences.primaryFontFamily, "JetBrains Mono")
        XCTAssertEqual(preferences.fallbackFontFamily, "Noto Sans CJK KR")
        XCTAssertEqual(preferences.fontSize, 16)
    }

    func testPreferencesUseDefaultKoreanFallbackFontWhenMissing() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhosttyConfigTests-\(UUID().uuidString)")
        let xdgConfig = home.appendingPathComponent(".config/ghostty/config")
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(
            at: xdgConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        theme = Dracula
        font-family = "JetBrains Mono"
        font-size = 16
        """.write(to: xdgConfig, atomically: true, encoding: .utf8)

        let preferences = GhosttyConfig.preferences(homeDirectory: home)

        XCTAssertEqual(preferences.primaryFontFamily, "JetBrains Mono")
        XCTAssertEqual(preferences.fallbackFontFamily, "Apple SD Gothic Neo")
    }

    func testUpdatingPreferencesReplacesManagedLinesAndPreservesOtherConfig() {
        let preferences = GhosttyPreferences(
            configURL: URL(fileURLWithPath: "/tmp/config"),
            themeName: "Dark Modern",
            fontSize: 15.5,
            primaryFontFamily: "SF Mono",
            fallbackFontFamily: "Apple SD Gothic Neo"
        )
        let contents = """
        # theme = Dracula
        shell-integration = zsh
        theme = Dracula
        font-family = "JetBrains Mono"
        font-size = 13
        keybind = cmd+d=text:\\x00d
        font-family = "Noto Sans CJK KR"
        """

        let updated = GhosttyConfig.updatingPreferences(preferences, in: contents)

        XCTAssertTrue(updated.contains("# theme = Dracula"))
        XCTAssertTrue(updated.contains("shell-integration = zsh"))
        XCTAssertTrue(updated.contains("keybind = cmd+d=text:\\x00d"))
        XCTAssertTrue(updated.contains("theme = Dark Modern"))
        XCTAssertTrue(updated.contains("font-size = 15.5"))
        XCTAssertTrue(updated.contains("font-family = \"SF Mono\""))
        XCTAssertTrue(updated.contains("font-family = \"Apple SD Gothic Neo\""))
        XCTAssertFalse(updated.contains("theme = Dracula\nfont-family"))
        XCTAssertFalse(updated.contains("font-size = 13"))
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

    func testParseColorThemeUsesInlineColorCommands() {
        let contents = """
        background = #101010
        foreground = #eeeeee
        cursor-color = #88c0d0
        palette = 4=#5e81ac
        """

        let theme = GhosttyConfig.parseColorTheme(from: contents)
        let colorTheme = theme?.theme(for: .dark)

        XCTAssertEqual(colorTheme?.background, "#101010")
        XCTAssertEqual(colorTheme?.foreground, "#eeeeee")
        XCTAssertEqual(colorTheme?.cursorColor, "#88c0d0")
        XCTAssertEqual(colorTheme?.palette[4], "#5e81ac")
    }

    func testParseColorThemeUsesNamedGhosttyTheme() {
        let contents = """
        theme = Dracula
        """

        let colorTheme = GhosttyConfig.parseColorTheme(from: contents)?.theme(for: .dark)

        XCTAssertEqual(colorTheme?.name, "Dracula")
    }

    func testParseColorThemeSupportsLightDarkThemePair() {
        let contents = """
        theme = light:Catppuccin Latte,dark:Catppuccin Mocha
        """

        let theme = GhosttyConfig.parseColorTheme(from: contents)

        XCTAssertEqual(theme?.theme(for: .light)?.name, "Catppuccin Latte")
        XCTAssertEqual(theme?.theme(for: .dark)?.name, "Catppuccin Mocha")
    }

    func testParseThemeNameUsesDarkThemeFromLightDarkPair() {
        let contents = """
        theme = light:Catppuccin Latte,dark:Catppuccin Mocha
        """

        XCTAssertEqual(GhosttyConfig.parseThemeName(from: contents), "Catppuccin Mocha")
    }

    func testParseKeybindsPreserveGhosttyActions() {
        let contents = """
        keybind = cmd+d=text:\\x00d
        keybind = cmd+shift+g=text:lazygit\\r
        keybind = cmd+q=quit
        """

        let keybinds = GhosttyConfig.parseKeybinds(from: contents)

        XCTAssertEqual(keybinds.count, 3)
        XCTAssertTrue(keybinds[0].matches(key: "d", modifiers: [.command]))
        XCTAssertEqual(keybinds[0].action, "text:\\x00d")
        XCTAssertTrue(keybinds[1].matches(key: "g", modifiers: [.command, .shift]))
        XCTAssertEqual(keybinds[1].action, "text:lazygit\\r")
        XCTAssertTrue(keybinds[2].matches(key: "q", modifiers: [.command]))
        XCTAssertEqual(keybinds[2].action, "quit")
    }
}
