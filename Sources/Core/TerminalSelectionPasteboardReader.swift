import AppKit

enum TerminalSelectionPasteboardReader {
    @MainActor
    static func readSelectedText(
        pasteboard: NSPasteboard = .general,
        copySelectionToPasteboard: () -> Bool
    ) -> String? {
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard copySelectionToPasteboard(),
              let selectedText = pasteboard.string(forType: .string)
        else {
            snapshot.restore(to: pasteboard)
            return nil
        }

        snapshot.restore(to: pasteboard)
        return selectedText
    }
}

private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
