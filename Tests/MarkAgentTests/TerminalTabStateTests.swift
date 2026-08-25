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

    @MainActor
    func testInactiveTerminalFocusPolicyResignsFirstResponder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = TerminalFocusTestView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(view)

        XCTAssertTrue(window.makeFirstResponder(view))
        XCTAssertTrue(window.firstResponder === view)

        TerminalFocusPolicy.resignIfNeeded(view)

        XCTAssertFalse(window.firstResponder === view)
    }

    @MainActor
    func testDeferredTerminalFocusUsesLatestWorkspaceActivity() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let firstView = TerminalFocusTestView(frame: window.contentView?.bounds ?? .zero)
        let secondView = TerminalFocusTestView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(firstView)
        window.contentView?.addSubview(secondView)
        let firstActivity = TerminalFocusActivity(isActive: true)
        let secondActivity = TerminalFocusActivity(isActive: false)

        TerminalFocusPolicy.requestFocus(firstView) { firstActivity.isActive }
        firstActivity.isActive = false
        secondActivity.isActive = true
        TerminalFocusPolicy.requestFocus(secondView) { secondActivity.isActive }

        let callbacksCompleted = expectation(description: "main queue focus callbacks completed")
        DispatchQueue.main.async {
            callbacksCompleted.fulfill()
        }
        await fulfillment(of: [callbacksCompleted], timeout: 1)

        XCTAssertFalse(window.firstResponder === firstView)
        XCTAssertTrue(window.firstResponder === secondView)
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

private final class TerminalFocusTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class TerminalFocusActivity {
    var isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }
}
