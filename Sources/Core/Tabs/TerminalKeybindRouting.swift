import GhosttyTerminal

enum TerminalKeybindRouting {
    static func isSnippetShortcut(key: String, modifiers: EventModifierMask) -> Bool {
        modifiers == [.command, .shift] && key.lowercased() == "c"
    }

    static func shouldSkipConfiguredTerminalKeybind(key: String, modifiers: EventModifierMask) -> Bool {
        let normalizedKey = key.lowercased()

        if isSnippetShortcut(key: key, modifiers: modifiers) {
            return true
        }

        if modifiers == [.command, .shift], ["f", "g"].contains(normalizedKey) {
            return true
        }

        if modifiers == [.command], normalizedKey == "w" {
            return true
        }

        return false
    }
}
