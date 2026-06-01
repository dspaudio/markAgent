import SwiftUI

struct GitChangesSidebar: View {
    var state: GitDiffState
    var isGitDiffTabOpen: Bool
    var onOpenFileInTab: (GitChangedFile) -> Void
    var onFocusFileInTab: (GitChangedFile) -> Void
    var mentionedFileIDs: Set<GitChangedFile.ID> = []

    @State private var previewFile: GitChangedFile?

    var body: some View {
        content
            .frame(maxHeight: .infinity)
        .onAppear {
            state.loadAllDiffs()
        }
        .onChange(of: state.changedFiles.map(\.id)) { _, _ in
            state.loadAllDiffs()
            syncPreviewFile()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let previewFile {
            diffPreview(for: previewFile)
        } else {
            fileList
        }
    }

    @ViewBuilder
    private var fileList: some View {
        Group {
            if !state.isInGitRepository {
                Text("현재 작업 경로는 Git 저장소가 아닙니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if state.changedFiles.isEmpty {
                Text("마지막 커밋 이후 변경된 파일이 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.changedFiles) { file in
                            GitChangedFileRow(
                                file: file,
                                diffResult: state.fileDiffs.first { $0.file.id == file.id }?.diffResult,
                                isLoadingDiff: state.isLoadingDiffs,
                                isSelected: state.selectedFile == file,
                                isMentionedInDocument: mentionedFileIDs.contains(file.id)
                            )
                            .onTapGesture {
                                selectFile(file)
                            }
                            .onTapGesture(count: 2) {
                                openPreview(for: file)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .opacity(state.isRefreshing ? 0.72 : 1)
            }
        }
    }

    private func openPreview(for file: GitChangedFile) {
        previewFile = file
        state.focus(file)
    }

    private func closePreview() {
        previewFile = nil
        state.clearSelection()
    }

    private func syncPreviewFile() {
        guard let previewFile else { return }

        if let refreshedFile = state.changedFiles.first(where: { $0.id == previewFile.id }) {
            self.previewFile = refreshedFile
        } else {
            closePreview()
        }
    }

    private func openPreviewInTab(_ file: GitChangedFile) {
        onOpenFileInTab(file)
        previewFile = nil
    }

    private func selectFile(_ file: GitChangedFile) {
        state.selectedFile = file
        guard isGitDiffTabOpen else { return }
        onFocusFileInTab(file)
    }

    @ViewBuilder
    private func diffPreview(for file: GitChangedFile) -> some View {
        FocusedEscapeContainer(onEscape: closePreview) {
            VStack(spacing: 0) {
                diffPreviewHeader(for: file)
                Divider()
                diffPreviewContent(for: file)
            }
        }
    }

    private func diffPreviewHeader(for file: GitChangedFile) -> some View {
        HStack(spacing: 8) {
            Button {
                closePreview()
            } label: {
                Label(String(localized: "Diff 미리보기 닫기"), systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Diff 미리보기 닫기"))

            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(String(localized: "Diff 미리보기"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                openPreviewInTab(file)
            } label: {
                Label(String(localized: "탭에서 열기"), systemImage: "rectangle.topthird.inset.filled")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Diff를 탭에서 열기"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func diffPreviewContent(for file: GitChangedFile) -> some View {
        if let fileDiff = state.fileDiffs.first(where: { $0.file.id == file.id }) {
            ScrollView {
                GitDiffFileSection(
                    fileDiff: fileDiff,
                    isMentionedInDocument: mentionedFileIDs.contains(file.id)
                )
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
        } else if state.isLoadingDiffs || state.isRefreshing {
            ProgressView("Diff 불러오는 중...")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("변경 없음")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GitChangedFileRow: View {
    let file: GitChangedFile
    let diffResult: DiffResult?
    let isLoadingDiff: Bool
    let isSelected: Bool
    let isMentionedInDocument: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(file.status.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isMentionedInDocument {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .help(String(localized: "열린 마크다운 문서에서 언급됨"))
                    }

                    diffSummary
                }

                Text(file.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }

    @ViewBuilder
    private var diffSummary: some View {
        if let diffResult {
            HStack(spacing: 4) {
                Text("+\(diffResult.addedCount)")
                    .foregroundStyle(.green)
                Text("-\(diffResult.removedCount)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .layoutPriority(1)
        } else if isLoadingDiff {
            Text("+… -…")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
