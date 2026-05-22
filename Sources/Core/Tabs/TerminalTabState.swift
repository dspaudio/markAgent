import AppKit
import Foundation
import GhosttyTerminal

@MainActor
@Observable
final class TerminalTabState {
    let id: UUID
    var workingDirectory: URL
    let terminalViewState: TerminalViewState

    var title: String
    private var configFontSize: Float?
    private var keybinds: [GhosttyKeybind]
    var didStart: Bool = false
    var onCloseRequested: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    weak var terminalView: AppTerminalView?

    init(id: UUID = UUID(), workingDirectory: URL) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.title = Self.title(for: workingDirectory)

        let configuration = Self.makeConfiguration()
        self.configFontSize = configuration.configFontSize
        self.keybinds = configuration.keybinds
        self.terminalViewState = configuration.viewState
    }

    func reloadConfiguration() {
        let userConfig = GhosttyConfig.userConfig()
        configFontSize = userConfig?.fontSize
        keybinds = userConfig?.keybinds ?? []

        let terminalConfiguration = Self.makeTerminalConfiguration(userConfig: userConfig)
        let configSource: TerminalController.ConfigSource = if let userConfig {
            .file(userConfig.url.path)
        } else {
            .none
        }
        let theme: TerminalTheme = userConfig != nil ? TerminalTheme() : .default

        _ = terminalViewState.controller.updateConfigSource(configSource)
        _ = terminalViewState.controller.setTheme(theme)
        _ = terminalViewState.controller.setTerminalConfiguration(terminalConfiguration)

        if didStart {
            terminalViewState.configuration = TerminalSurfaceOptions(
                backend: .exec,
                fontSize: configFontSize,
                workingDirectory: workingDirectory.path
            )

            terminalViewState.onClose = { [weak self] _ in
                Task { @MainActor in
                    self?.onCloseRequested?()
                }
            }

            terminalView?.controller = terminalViewState.controller
            terminalView?.configuration = terminalViewState.configuration
        }
    }

    private static func makeConfiguration() -> (configFontSize: Float?, keybinds: [GhosttyKeybind], viewState: TerminalViewState) {
        let userConfig = GhosttyConfig.userConfig()
        let configFontSize = userConfig?.fontSize
        let keybinds = userConfig?.keybinds ?? []
        let terminalConfiguration = makeTerminalConfiguration(userConfig: userConfig)

        let configSource: TerminalController.ConfigSource = if let userConfig {
            .file(userConfig.url.path)
        } else {
            .none
        }
        let theme: TerminalTheme = userConfig != nil ? TerminalTheme() : .default

        let viewState = TerminalViewState(
            configSource: configSource,
            theme: theme,
            terminalConfiguration: terminalConfiguration
        )

        return (configFontSize, keybinds, viewState)
    }

    private static func makeTerminalConfiguration(userConfig: GhosttyConfig?) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            for fontFamily in userConfig?.fontFamilies ?? [] {
                builder.withFontFamily(fontFamily)
            }
            if let fontSize = userConfig?.fontSize {
                builder.withFontSize(fontSize)
            }
        }
    }

    func startIfNeeded() {
        guard !didStart else {
            refreshTitleFromTerminalContext()
            return
        }

        didStart = true
        terminalViewState.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: configFontSize,
            workingDirectory: workingDirectory.path
        )

        terminalViewState.onClose = { [weak self] _ in
            Task { @MainActor in
                self?.onCloseRequested?()
            }
        }

        refreshTitleFromTerminalContext()
    }

    func refreshTitleFromTerminalContext() {
        guard !terminalViewState.title.isEmpty else { return }
        title = terminalViewState.title
    }

    func updateWorkingDirectory(_ url: URL) {
        workingDirectory = url
        title = Self.title(for: url)
        onDirectoryChanged?(url)
    }

    func close() {
        terminalViewState.onClose = nil
        didStart = false
    }

    func sendConfiguredKeybind(_ event: NSEvent, key: String, modifiers: EventModifierMask) -> Bool {
        guard keybinds.contains(where: { $0.matches(key: key, modifiers: modifiers) }) else {
            return false
        }

        guard let terminalView else { return false }
        terminalView.window?.makeFirstResponder(terminalView)
        terminalView.keyDown(with: event)
        return true
    }

    private static func title(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path == NSHomeDirectory() {
            return "~"
        }

        let title = url.lastPathComponent
        return title.isEmpty ? path : title
    }
}
