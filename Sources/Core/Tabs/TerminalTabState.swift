import Foundation
import GhosttyTerminal

@MainActor
@Observable
final class TerminalTabState {
    let id: UUID
    var workingDirectory: URL
    let terminalViewState: TerminalViewState

    var title: String
    var didStart: Bool = false
    var onCloseRequested: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    weak var terminalView: AppTerminalView?

    init(id: UUID = UUID(), workingDirectory: URL) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.title = workingDirectory.lastPathComponent

        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty/config")
            .path
        let configExists = FileManager.default.fileExists(atPath: configPath)

        let configSource: TerminalController.ConfigSource = configExists
            ? .file(configPath)
            : .none
        let theme: TerminalTheme = configExists ? TerminalTheme() : .default

        self.terminalViewState = TerminalViewState(
            configSource: configSource,
            theme: theme
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
