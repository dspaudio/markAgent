import AppKit

enum PromptSnippetClipboard {
    @MainActor
    static func copy(_ body: String, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
    }
}
