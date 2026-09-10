import AppKit

final class MarkAgentWindow: NSWindow {
    var navigationKeybindHandler: ((NSEvent) -> Bool)?
    var terminalKeybindHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if navigationKeybindHandler?(event) == true {
                return true
            }
            if terminalKeybindHandler?(event) == true {
                return true
            }
            if let mainMenu = NSApp.mainMenu {
                if mainMenu.performKeyEquivalent(with: event) {
                    return true
                }
                if mainMenu.hasKeyEquivalent(for: event) {
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum NumberNavigationShortcut: Equatable {
    case workspace(Int)
    case tab(Int)

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard modifiers == .command || modifiers == [.command, .shift] else { return nil }

        let number: Int
        switch event.keyCode {
        case 18, 83: number = 1
        case 19, 84: number = 2
        case 20, 85: number = 3
        case 21, 86: number = 4
        case 23, 87: number = 5
        case 22, 88: number = 6
        case 26, 89: number = 7
        case 28, 91: number = 8
        case 25, 92: number = 9
        case 29, 82: number = 10
        default: return nil
        }

        self = modifiers.contains(.shift) ? .tab(number) : .workspace(number)
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
