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
    private let userConfigProvider: () -> GhosttyConfig?

    init(
        id: UUID = UUID(),
        workingDirectory: URL,
        userConfigProvider: @escaping () -> GhosttyConfig? = { GhosttyConfig.userConfig() }
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.title = Self.title(for: workingDirectory)
        self.userConfigProvider = userConfigProvider

        let configuration = Self.makeConfiguration(userConfig: userConfigProvider())
        self.configFontSize = configuration.configFontSize
        self.keybinds = configuration.keybinds
        self.terminalViewState = configuration.viewState
    }

    func reloadConfiguration() {
        let userConfig = userConfigProvider()
        configFontSize = userConfig?.fontSize
        keybinds = userConfig?.keybinds ?? []

        let terminalConfiguration = Self.makeTerminalConfiguration(userConfig: userConfig)
        let configSource = Self.configSource(for: userConfig)
        let theme = Self.makeTerminalTheme(userConfig: userConfig)

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

    private static func makeConfiguration(userConfig: GhosttyConfig?) -> (configFontSize: Float?, keybinds: [GhosttyKeybind], viewState: TerminalViewState) {
        let configFontSize = userConfig?.fontSize
        let keybinds = userConfig?.keybinds ?? []
        let terminalConfiguration = makeTerminalConfiguration(userConfig: userConfig)

        let configSource = configSource(for: userConfig)
        let theme = makeTerminalTheme(userConfig: userConfig)

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

    private static func makeTerminalTheme(userConfig: GhosttyConfig?) -> TerminalTheme {
        guard let userConfig else { return .default }
        guard let colorTheme = userConfig.colorTheme else { return TerminalTheme() }

        let lightTheme = colorTheme.light ?? colorTheme.dark
        let darkTheme = colorTheme.dark ?? colorTheme.light

        return TerminalTheme(
            light: makeTerminalConfiguration(colorTheme: lightTheme),
            dark: makeTerminalConfiguration(colorTheme: darkTheme)
        )
    }

    private static func makeTerminalConfiguration(colorTheme: TerminalColorTheme?) -> TerminalConfiguration {
        guard let colorTheme else { return TerminalConfiguration() }

        return TerminalConfiguration { builder in
            builder.withBackground(ghosttyColor(colorTheme.background))
            builder.withForeground(ghosttyColor(colorTheme.foreground))

            if let cursorColor = colorTheme.cursorColor {
                builder.withCursorColor(ghosttyColor(cursorColor))
            }

            if let selectionBackground = colorTheme.selectionBackground {
                builder.withSelectionBackground(ghosttyColor(selectionBackground))
            }

            if let selectionForeground = colorTheme.selectionForeground {
                builder.withSelectionForeground(ghosttyColor(selectionForeground))
            }

            for index in colorTheme.palette.keys.sorted() {
                guard let color = colorTheme.palette[index] else { continue }
                builder.withPalette(index, color: ghosttyColor(color))
            }
        }
    }

    private static func ghosttyColor(_ color: String) -> String {
        let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") || trimmed.lowercased().hasPrefix("0x") {
            return trimmed
        }
        return "#\(trimmed)"
    }

    static func configSource(for userConfig: GhosttyConfig?) -> TerminalController.ConfigSource {
        guard let userConfig else { return .none }
        if userConfig.colorTheme != nil {
            return .generated(contentsWithoutActiveThemeLines(userConfig.contents))
        }
        return .generated(userConfig.contents)
    }

    private static func contentsWithoutActiveThemeLines(_ contents: String) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return true }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return true }
            return parts[0].trimmingCharacters(in: .whitespaces) != "theme"
        }

        var updated = filteredLines.joined(separator: "\n")
        if !updated.isEmpty, !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        return updated
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
        let resolvedURL = Self.normalizedWorkingDirectory(from: url.path) ?? url
        title = Self.title(for: resolvedURL)
        workingDirectory = resolvedURL
        onDirectoryChanged?(resolvedURL)
    }

    func updateWorkingDirectory(_ path: String) {
        guard let url = Self.normalizedWorkingDirectory(from: path) else { return }
        updateWorkingDirectory(url)
    }

    nonisolated static func normalizedWorkingDirectory(from rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expandedPath: String
        if let url = URL(string: trimmed), url.isFileURL {
            expandedPath = url.path
        } else {
            expandedPath = NSString(string: trimmed).expandingTildeInPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath().standardizedFileURL
    }

    func close() {
        terminalViewState.onClose = nil
        didStart = false
    }

    func sendConfiguredKeybind(_ event: NSEvent, key: String, modifiers: EventModifierMask) -> Bool {
        guard let keybind = keybinds.first(where: { $0.matches(key: key, modifiers: modifiers) }) else {
            return false
        }

        guard let terminalView else { return false }

        if terminalView.performBindingAction(keybind.action) {
            return true
        }

        if let text = keybind.decodedTextAction {
            terminalView.sendText(text)
            return true
        }

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
