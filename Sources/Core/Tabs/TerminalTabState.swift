import Foundation
import GhosttyTerminal

@MainActor
@Observable
final class TerminalTabState {
    let id: UUID
    var workingDirectory: URL
    let terminalViewState: TerminalViewState

    var title: String
    private let configFontSize: Float?
    var didStart: Bool = false
    var onCloseRequested: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    weak var terminalView: AppTerminalView?

    init(id: UUID = UUID(), workingDirectory: URL) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.title = workingDirectory.lastPathComponent

        let userConfig = GhosttyConfig.userConfig()
        self.configFontSize = userConfig?.fontSize
        let terminalConfiguration = TerminalConfiguration { builder in
            for fontFamily in userConfig?.fontFamilies ?? [] {
                builder.withFontFamily(fontFamily)
            }
            if let fontSize = userConfig?.fontSize {
                builder.withFontSize(fontSize)
            }
        }

        let configSource: TerminalController.ConfigSource = if let userConfig {
            .file(userConfig.url.path)
        } else {
            .none
        }
        let theme: TerminalTheme = userConfig != nil ? TerminalTheme() : .default

        self.terminalViewState = TerminalViewState(
            configSource: configSource,
            theme: theme,
            terminalConfiguration: terminalConfiguration
        )
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

    func close() {
        terminalViewState.onClose = nil
        didStart = false
    }
}
