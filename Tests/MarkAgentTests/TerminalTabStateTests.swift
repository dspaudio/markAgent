import AppKit
import GhosttyTerminal
import XCTest
@testable import ma

final class TerminalTabStateTests: XCTestCase {
    @MainActor
    func testSearchAwareTerminalViewConsumesSearchShortcuts() throws {
        let view = SearchAwareTerminalView()
        var requestedModes: [SidebarSearchMode] = []
        view.onSearchShortcut = { requestedModes.append($0) }

        XCTAssertTrue(view.performKeyEquivalent(with: try keyEvent(key: "f", keyCode: 3, modifiers: [.command, .shift])))
        XCTAssertTrue(view.performKeyEquivalent(with: try keyEvent(key: "g", keyCode: 5, modifiers: [.command, .shift])))
        XCTAssertFalse(view.performKeyEquivalent(with: try keyEvent(key: "f", keyCode: 3, modifiers: [.command])))
        XCTAssertEqual(requestedModes, [.files, .grep])
    }

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
    func testNamedGhosttyThemeRendersExplicitTerminalColors() {
        let contents = """
        theme = Catppuccin Latte
        background-opacity = 0.9
        """
        let state = TerminalTabState(
            workingDirectory: FileManager.default.temporaryDirectory,
            userConfigProvider: {
                GhosttyConfig(
                    url: URL(fileURLWithPath: "/tmp/ghostty-config"),
                    contents: contents,
                    fontFamilies: [],
                    fontSize: nil,
                    colorTheme: GhosttyConfig.parseColorTheme(from: contents),
                    keybinds: []
                )
            }
        )

        let renderedConfig = state.terminalViewState.renderedConfig

        XCTAssertTrue(renderedConfig.contains("background = #eff1f5"))
        XCTAssertTrue(renderedConfig.contains("foreground = #4c4f69"))
        XCTAssertTrue(renderedConfig.contains("cursor-color = #dc8a78"))
        XCTAssertTrue(renderedConfig.contains("palette = 4=#1e66f5"))
        XCTAssertTrue(renderedConfig.contains("background-opacity = 0.9"))
        XCTAssertFalse(renderedConfig.contains("theme = Catppuccin Latte"))
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

    func testNormalizedWorkingDirectoryAcceptsFileURLFromOSC7() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalTabStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURLString = directory.absoluteString
        let resolved = TerminalTabState.normalizedWorkingDirectory(from: fileURLString)

        XCTAssertEqual(resolved?.standardizedFileURL, directory.resolvingSymlinksInPath().standardizedFileURL)
    }

    @MainActor
    func testWorkingDirectoryIgnoresInvalidPathUpdates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalTabStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = TerminalTabState(workingDirectory: directory)
        state.updateWorkingDirectory("file:///definitely/missing/markagent/path")

        XCTAssertEqual(state.workingDirectory, directory)
    }

    private func keyEvent(key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: key.uppercased(),
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
