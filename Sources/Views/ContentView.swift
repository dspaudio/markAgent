import SwiftUI

struct ContentView: View {
    var document: MarkdownDocument

    @State private var isTemplatePickerPresented = false

    var body: some View {
        Group {
            if let errorMessage = document.errorMessage {
                errorView(message: errorMessage)
            } else if !document.isLoaded {
                loadingView
            } else {
                switch document.viewMode {
                case .preview:
                    if document.editableContent.isEmpty {
                        emptyDocumentView
                    } else if document.showDiff, let diffResult = document.diffResult {
                        DiffOverlayView(diffResult: diffResult) {
                            document.showDiff = false
                        }
                    } else {
                        previewContent
                    }
                case .edit:
                    EditorView(document: document)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    document.viewMode = document.viewMode == .preview ? .edit : .preview
                } label: {
                    Label(
                        document.viewMode == .preview ? "편집" : "미리보기",
                        systemImage: document.viewMode == .preview ? "pencil" : "eye"
                    )
                }
                .help("미리보기/편집 전환 (⌘E)")
                .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    document.showDiff.toggle()
                } label: {
                    Label(
                        document.showDiff ? "Diff 숨기기" : "Diff 보기",
                        systemImage: "arrow.left.arrow.right.circle"
                    )
                }
                .help("Diff 보기 토글 (⌘D)")
                .keyboardShortcut("d", modifiers: .command)
                .disabled(document.diffResult == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    isTemplatePickerPresented = true
                } label: {
                    Label("템플릿", systemImage: "doc.badge.plus")
                }
                .help("템플릿 삽입 (⌘T)")
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        // 외부 수정 충돌 경고
        .alert(
            "파일이 외부에서 수정되었습니다",
            isPresented: Binding(
                get: { document.isExternalUpdatePending },
                set: { if !$0 { document.rejectExternalUpdate() } }
            )
        ) {
            Button("외부 변경 로드") { document.acceptExternalUpdate() }
            Button("내 변경 유지") { document.rejectExternalUpdate() }
            Button("취소", role: .cancel) { document.rejectExternalUpdate() }
        } message: {
            Text("편집 중인 내용과 파일의 내용이 다릅니다. 어떻게 하시겠습니까?")
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePicker(
                onApply: { renderedContent in
                    document.editableContent = renderedContent
                    document.isLoaded = true
                    document.viewMode = .edit
                    isTemplatePickerPresented = false
                },
                onDismiss: {
                    isTemplatePickerPresented = false
                }
            )
        }
    }

    private var previewContent: some View {
        ScrollView {
            renderMarkdown(document.editableContent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("파일을 로드하는 중...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDocumentView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("빈 문서입니다.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
