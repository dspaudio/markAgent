import AppKit
import GhosttyTerminal

final class SearchAwareTerminalView: AppTerminalView {
    var onSearchShortcut: ((SidebarSearchMode) -> Void)?
    var onSnippetShortcut: ((String) -> Void)?
    var selectedTextProvider: (() -> String?)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleSnippetShortcut(event) {
            return true
        }
        if handleSearchShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleSnippetShortcut(event) {
            return
        }
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

    private func handleSnippetShortcut(_ event: NSEvent) -> Bool {
        guard isSnippetShortcut(event) else { return false }
        guard let selectedText = selectedTextForSnippet(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return true
        }

        onSnippetShortcut?(selectedText)
        return true
    }

    private func isSnippetShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }

        return key == "c"
    }

    private func selectedTextForSnippet() -> String? {
        if let selectedTextProvider {
            return selectedTextProvider()
        }

        return TerminalSelectionPasteboardReader.readSelectedText {
            performBindingAction("copy_to_clipboard")
        }
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
