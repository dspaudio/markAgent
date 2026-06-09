import AppKit

enum TerminalSnippetSelectionSaver {
    @MainActor
    static func saveSelection(
        to store: PromptSnippetStore,
        pasteboard: NSPasteboard = .general,
        copySelectionToPasteboard: () -> Bool,
        onSaved: () -> Void = {}
    ) -> Bool {
        guard let selectedText = TerminalSelectionPasteboardReader.readSelectedText(
            pasteboard: pasteboard,
            copySelectionToPasteboard: copySelectionToPasteboard
        ) else {
            return true
        }

        guard store.add(body: selectedText) != nil else {
            return true
        }

        onSaved()
        return true
    }
}
