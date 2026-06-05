import AppKit
import GhosttyTerminal

final class SearchAwareTerminalView: AppTerminalView {
    var onSearchShortcut: ((SidebarSearchMode) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleSearchShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleSearchShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleSearchShortcut(_ event: NSEvent) -> Bool {
        guard let mode = sidebarSearchMode(for: event) else { return false }
        onSearchShortcut?(mode)
        return true
    }

    private func sidebarSearchMode(for event: NSEvent) -> SidebarSearchMode? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return nil }

        switch key {
        case "f":
            return .files
        case "g":
            return .grep
        default:
            return nil
        }
    }
}
