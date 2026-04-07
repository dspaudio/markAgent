import SwiftUI

struct EditorView: View {
    @Bindable var document: MarkdownDocument
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        TextEditor(text: $document.editableContent)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.textBackgroundColor))
            .focused($isEditorFocused)
            .onAppear {
                // 편집 모드 진입 시 TextEditor에 포커스 부여
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isEditorFocused = true
                }
            }
    }
}
