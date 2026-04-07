import SwiftUI

struct EditorView: View {
    @Bindable var document: MarkdownDocument

    var body: some View {
        TextEditor(text: $document.editableContent)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.textBackgroundColor))
    }
}
