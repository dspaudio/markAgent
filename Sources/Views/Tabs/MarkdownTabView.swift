import SwiftUI

struct MarkdownTabView: View {
    var state: MarkdownTabState
    var isActive: Bool
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void

    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var cachedPreviewSource: String?
    @State private var cachedPreviewBaseURL: URL?
    @State private var cachedPreview: AnyView?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            localHeaderToolbar
            Divider()
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if state.document.viewMode == .preview {
                    refreshPreviewIfNeeded()
                }
            }
            .onChange(of: state.document.viewMode) { _, mode in
                switch mode {
                case .preview:
                    refreshPreviewIfNeeded()
                case .rawEdit:
                    clearPreviewCache()
                }
            }
            .onChange(of: state.document.fileURL) { _, _ in
                if state.document.viewMode == .preview {
                    refreshPreviewIfNeeded(force: true)
                }
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
            showsInlineToolbar: false,
            rendersMarkdownStyle: false,
            isActive: isActive,
            externalSelectedRange: $selectedRange
        )
    }

    private var localHeaderToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if state.document.supportsPreview {
                    modeButton(.preview, title: String(localized: "Preview"), systemImage: "eye")
                }
                    modeButton(.rawEdit, title: String(localized: "Raw Edit"), systemImage: "square.and.pencil")
            }

            if state.document.supportsPreview {
                Divider()
                    .frame(height: 22)

                HStack(spacing: 6) {
                    editButton("H", help: String(localized: "제목"), action: .heading)
                    editButton("B", help: String(localized: "굵게"), action: .bold)
                    editButton("I", help: String(localized: "기울임"), action: .italic)
                        .italic()
                    editButton(systemImage: "link", help: String(localized: "링크"), action: .link)
                    editButton(systemImage: "list.bullet", help: String(localized: "글머리 기호"), action: .unorderedList)
                    editButton(systemImage: "list.number", help: String(localized: "번호 목록"), action: .orderedList)
                    editButton(systemImage: "checklist", help: String(localized: "체크리스트"), action: .checklist)
                    editButton(systemImage: "quote.opening", help: String(localized: "인용"), action: .quote)
                    editButton(systemImage: "chevron.left.forwardslash.chevron.right", help: String(localized: "인라인 코드"), action: .inlineCode)
                }
                .disabled(state.document.viewMode != .rawEdit)
                .opacity(state.document.viewMode == .rawEdit ? 1 : 0.45)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(appColors?.panel ?? Color(NSColor.controlBackgroundColor))
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
            Image(systemName: systemImage)
                .frame(width: 28, height: 26)
                .foregroundStyle(isSelected ? (appColors?.accent ?? Color.accentColor) : (appColors?.foreground ?? Color.primary))
        }
        .help(String(format: String(localized: "%@ 보기"), title))
    }

    private func editButton(_ title: String, help: String, action: MarkdownEditAction) -> some View {
        Button {
            MarkdownEditingController.apply(action, to: state.document, selectedRange: $selectedRange)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .help(help)
    }

    private func editButton(systemImage: String, help: String, action: MarkdownEditAction) -> some View {
        Button {
            MarkdownEditingController.apply(action, to: state.document, selectedRange: $selectedRange)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .help(help)
    }

    private var previewContent: some View {
        ScrollView {
            Group {
                if let cachedPreview {
                    cachedPreview
                } else {
                    EmptyView()
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .onAppear {
            refreshPreviewIfNeeded()
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

    private func refreshPreviewIfNeeded(force: Bool = false) {
        let source = state.document.editableContent
        let baseURL = documentImageBaseURL

        guard force || cachedPreview == nil || cachedPreviewSource != source || cachedPreviewBaseURL != baseURL else {
            return
        }

        cachedPreviewSource = source
        cachedPreviewBaseURL = baseURL
        cachedPreview = renderMarkdown(source, baseURL: baseURL)
    }

    private func clearPreviewCache() {
        cachedPreview = nil
        cachedPreviewSource = nil
        cachedPreviewBaseURL = nil
    }
}
