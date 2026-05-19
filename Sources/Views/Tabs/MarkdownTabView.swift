import SwiftUI

struct MarkdownTabView: View {
    var state: MarkdownTabState
    var isActive: Bool
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if isActive {
                        if state.document.supportsPreview {
                            modeButton(.preview, title: "Preview", systemImage: "eye")
                        }
                        modeButton(.rawEdit, title: "Raw Edit", systemImage: "square.and.pencil")
                    }
                }
            }
            .alert(
                "파일이 외부에서 수정되었습니다",
                isPresented: Binding(
                    get: { state.document.isExternalUpdatePending },
                    set: { if !$0 { state.document.rejectExternalUpdate() } }
                )
            ) {
                Button("외부 변경 로드") { state.document.acceptExternalUpdate() }
                Button("내 변경 유지") { state.document.rejectExternalUpdate() }
                Button("취소", role: .cancel) { state.document.rejectExternalUpdate() }
            } message: {
                Text("편집 중인 내용과 파일의 내용이 다릅니다. 어떻게 하시겠습니까?")
            }
            .onChange(of: state.document.editableContent) { _, _ in
                onDocumentChanged()
            }
            .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
            .foregroundStyle(appColors?.foreground ?? Color.primary)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let errorMessage = state.document.errorMessage {
            errorView(message: errorMessage)
        } else if !state.document.isLoaded {
            loadingView
        } else {
            switch state.document.viewMode {
            case .preview:
                if !state.document.supportsPreview {
                    rawEditor
                } else if state.document.editableContent.isEmpty {
                    emptyDocumentView
                } else if state.document.showDiff, let diffResult = state.document.diffResult {
                    DiffOverlayView(diffResult: diffResult, baseURL: documentImageBaseURL) {
                        state.document.showDiff = false
                    }
                } else {
                    previewContent
                }
            case .rawEdit:
                rawEditor
            }
        }
    }

    private var rawEditor: some View {
        EditorView(
            document: state.document,
            showsInlineToolbar: state.document.supportsPreview,
            rendersMarkdownStyle: false,
            isActive: isActive
        )
    }

    private func modeButton(
        _ mode: ViewMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = state.document.viewMode == mode

        return Button {
            state.document.viewMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isSelected ? (appColors?.accent ?? Color.accentColor) : (appColors?.foreground ?? Color.primary))
        }
        .help("\(title) 보기")
    }

    private var previewContent: some View {
        ScrollView {
            renderMarkdown(state.document.editableContent, baseURL: documentImageBaseURL)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private var documentImageBaseURL: URL? {
        state.document.fileURL?.deletingLastPathComponent()
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

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
}
