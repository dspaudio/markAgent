import AppKit

final class MarkAgentWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let mainMenu = NSApp.mainMenu {
            if mainMenu.performKeyEquivalent(with: event) {
                return true
            }
            if mainMenu.hasKeyEquivalent(for: event) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private extension NSMenu {
    func hasKeyEquivalent(for event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
            return false
        }

        return items.contains { item in
            if item.submenu?.hasKeyEquivalent(for: event) == true {
                return true
            }

            guard !item.keyEquivalent.isEmpty,
                  item.keyEquivalent.lowercased() == key else {
                return false
            }

            let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let itemModifiers = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
            return eventModifiers == itemModifiers
        }
    }
}
