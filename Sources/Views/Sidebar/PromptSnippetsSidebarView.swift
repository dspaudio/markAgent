import SwiftUI

struct PromptSnippetsSidebarView: View {
    var store: PromptSnippetStore
    /// 활성 터미널에 뷰가 붙어 있을 때만 보내기 버튼을 활성화한다.
    /// 클로저로 받아 이 뷰의 body에서 평가한다. 터미널 뷰는 갱신마다 `terminalView`를 다시 쓰므로
    /// 상위 쉘 body에서 읽으면 관찰 추적이 쉘 전체를 반복 재렌더하게 된다.
    var canSendToTerminal: () -> Bool = { false }
    var onSendToTerminal: ((PromptSnippet) -> Void)?

    @State private var editor: PromptSnippetEditorState?
    @State private var snippetPendingDeletion: PromptSnippet?
    @State private var copiedSnippetID: PromptSnippet.ID?

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            content
        }
        .sheet(item: $editor) { state in
            PromptSnippetEditorView(state: state) { body in
                save(state: state, body: body)
            }
        }
        .alert("스니펫을 삭제할까요?", isPresented: deleteAlertBinding) {
            Button("취소", role: .cancel) {
                snippetPendingDeletion = nil
            }
            Button("삭제", role: .destructive) {
                if let snippetPendingDeletion {
                    store.delete(snippetPendingDeletion)
                }
                snippetPendingDeletion = nil
            }
        } message: {
            Text("삭제한 스니펫은 복구할 수 없습니다.")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("저장된 프롬프트")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                editor = PromptSnippetEditorState(snippet: nil)
            } label: {
                Label(String(localized: "추가"), systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help(String(localized: "스니펫 추가"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.snippets.isEmpty {
            Text("저장된 스니펫이 없습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.snippets) { snippet in
                        snippetRow(snippet, isCopied: copiedSnippetID == snippet.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }

    func snippetRow(_ snippet: PromptSnippet, isCopied: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.body)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if isCopied {
                    Text("복사됨")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
            Button {
                onSendToTerminal?(snippet)
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.plain)
            .disabled(!canSendToTerminal() || onSendToTerminal == nil)
            .help(String(localized: "터미널로 보내기"))
            .accessibilityIdentifier("snippet.sendToTerminal")

            Button {
                editor = PromptSnippetEditorState(snippet: snippet)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(String(localized: "편집"))

            Button {
                snippetPendingDeletion = snippet
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help(String(localized: "삭제"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
        .onTapGesture {
            copy(snippet)
        }
        .help(String(localized: "클릭해서 스니펫 복사"))
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { snippetPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    snippetPendingDeletion = nil
                }
            }
        )
    }

    private func save(state: PromptSnippetEditorState, body: String) {
        if let snippet = state.snippet {
            _ = store.update(snippet, body: body)
        } else {
            _ = store.add(body: body)
        }
    }

    private func copy(_ snippet: PromptSnippet) {
        PromptSnippetClipboard.copy(snippet.body)
        copiedSnippetID = snippet.id
        Task { [id = snippet.id] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                guard copiedSnippetID == id else { return }
                copiedSnippetID = nil
            }
        }
    }

}

private struct PromptSnippetEditorState: Identifiable {
    let id = UUID()
    let snippet: PromptSnippet?
}

private struct PromptSnippetEditorView: View {
    let state: PromptSnippetEditorState
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bodyText: String

    init(state: PromptSnippetEditorState, onSave: @escaping (String) -> Void) {
        self.state = state
        self.onSave = onSave
        _bodyText = State(initialValue: state.snippet?.body ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextEditor(text: $bodyText)
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(state.snippet == nil ? "스니펫 추가" : "스니펫 편집"))
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Button("취소") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("저장") {
                onSave(bodyText)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
