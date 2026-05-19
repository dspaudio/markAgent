import Foundation
import GhosttyTerminal
import GhosttyTheme

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

        let theme: TerminalTheme
        if configExists, let themeName = Self.extractThemeName(from: configPath),
           let ghosttyTheme = GhosttyThemeCatalog.theme(named: themeName) {
            theme = ghosttyTheme.toTerminalTheme()
        } else {
            theme = TerminalTheme.default
        }

        let configSource: TerminalController.ConfigSource = configExists
            ? .file(configPath)
            : .none

        self.terminalViewState = TerminalViewState(
            configSource: configSource,
            theme: theme
        )
    }

    private static func extractThemeName(from path: String) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            if trimmed.hasPrefix("theme") {
                let parts = trimmed.components(separatedBy: "=")
                guard parts.count >= 2 else { continue }
                return parts[1]
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
            }
        }
        return nil
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
