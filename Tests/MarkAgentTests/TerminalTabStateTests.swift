import GhosttyTerminal
import XCTest
@testable import ma

final class TerminalTabStateTests: XCTestCase {
    @MainActor
    func testConfigSourceUsesContentsSoReloadSeesEditsAtSamePath() {
        let firstConfig = GhosttyConfig(
            url: URL(fileURLWithPath: "/tmp/ghostty-config"),
            contents: "font-size = 14",
            fontFamilies: [],
            fontSize: 14,
            colorTheme: nil,
            keybinds: []
        )
        let editedConfig = GhosttyConfig(
            url: firstConfig.url,
            contents: "font-size = 18",
            fontFamilies: [],
            fontSize: 18,
            colorTheme: nil,
            keybinds: []
        )

        XCTAssertEqual(TerminalTabState.configSource(for: firstConfig), .generated("font-size = 14"))
        XCTAssertEqual(TerminalTabState.configSource(for: editedConfig), .generated("font-size = 18"))
        XCTAssertNotEqual(TerminalTabState.configSource(for: firstConfig), TerminalTabState.configSource(for: editedConfig))
    }

    @MainActor
    func testTerminalTabStateCanDeallocateAfterConfigurationReload() {
        weak var weakState: TerminalTabState?
        var currentContents = "font-size = 14"
        var currentFontSize: Float = 14

        autoreleasepool {
            let state = TerminalTabState(
                workingDirectory: FileManager.default.temporaryDirectory,
                userConfigProvider: {
                    GhosttyConfig(
                        url: URL(fileURLWithPath: "/tmp/ghostty-config"),
                        contents: currentContents,
                        fontFamilies: [],
                        fontSize: currentFontSize,
                        colorTheme: nil,
                        keybinds: []
                    )
                }
            )
            state.startIfNeeded()
            currentContents = "font-size = 18"
            currentFontSize = 18
            state.reloadConfiguration()
            state.close()
            weakState = state
        }

        XCTAssertNil(weakState)
    }
}
