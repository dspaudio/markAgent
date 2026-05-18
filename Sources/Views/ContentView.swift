import SwiftUI

struct ContentView: View {
    var document: MarkdownDocument
    var recentStore: RecentDocumentStore
    var onNewDocument: () -> Void
    var onOpenFile: () -> Void
    var onOpenRecent: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RecentDocumentsSidebar(
                store: recentStore,
                currentFileURL: document.fileURL,
                onOpenFile: onOpenFile,
                onOpen: onOpenRecent
            )

            Divider()

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onNewDocument) {
                    Label("새 문서", systemImage: "doc.badge.plus")
                }
                .help("새 문서 (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: onOpenFile) {
                    Label("열기", systemImage: "folder")
                }
                .help("파일 열기 (⌘O)")
                .keyboardShortcut("o", modifiers: .command)
            }

            ToolbarItemGroup(placement: .automatic) {
                modeButton(.preview, title: "Preview", systemImage: "eye", shortcut: "1")
                modeButton(.rawEdit, title: "Raw Edit", systemImage: "square.and.pencil", shortcut: "2")
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

        }
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
    }

    @ViewBuilder
    private var detailContent: some View {
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
            case .rawEdit:
                EditorView(
                    document: document,
                    showsInlineToolbar: true,
                    rendersMarkdownStyle: false
                )
            }
        }
    }

    private func modeButton(
        _ mode: ViewMode,
        title: String,
        systemImage: String,
        shortcut: KeyEquivalent
    ) -> some View {
        let isSelected = document.viewMode == mode

        return Button {
            document.viewMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .help("\(title) 보기")
        .keyboardShortcut(shortcut, modifiers: .command)
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
            Button(action: onOpenFile) {
                Label("파일 열기", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
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
