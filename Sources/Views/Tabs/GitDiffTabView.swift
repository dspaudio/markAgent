import SwiftUI

struct GitDiffTabView: View {
    var state: GitDiffState
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .onAppear {
            state.loadAllDiffs()
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Files changed")
                    .font(.system(size: 14, weight: .bold))

                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if state.isLoadingDiffs || state.isRefreshing {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 16, height: 16)
            }

            Button {
                if let root = state.repositoryRoot {
                    state.refresh(for: root)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("새로고침")
            .disabled(state.isRefreshing || state.repositoryRoot == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = state.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if state.changedFiles.isEmpty {
            Text("마지막 커밋 이후 변경된 파일이 없습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if state.fileDiffs.isEmpty && state.isLoadingDiffs {
            ProgressView("Diff 불러오는 중...")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(state.fileDiffs) { fileDiff in
                            GitDiffFileSection(fileDiff: fileDiff)
                                .id(fileDiff.id)
                        }
                    }
                    .padding(14)
                }
                .onAppear {
                    scrollToFocusedFile(with: proxy, animated: false)
                }
                .onChange(of: state.focusRequestID) { _, _ in
                    scrollToFocusedFile(with: proxy, animated: true)
                }
                .onChange(of: state.fileDiffs.map(\.id)) { _, _ in
                    scrollToFocusedFile(with: proxy, animated: true)
                }
            }
        }
    }

    private var summaryText: String {
        let fileCount = state.changedFiles.count
        let addedCount = state.fileDiffs.reduce(0) { $0 + $1.diffResult.addedCount }
        let removedCount = state.fileDiffs.reduce(0) { $0 + $1.diffResult.removedCount }
        let repositoryName = state.repositoryRoot?.lastPathComponent ?? "Git 저장소"
        return "\(repositoryName) · \(fileCount)개 파일 · +\(addedCount) -\(removedCount)"
    }

    private func scrollToFocusedFile(with proxy: ScrollViewProxy, animated: Bool) {
        guard isActive, let focusedFileID = state.focusedFileID else { return }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(focusedFileID, anchor: .top)
                }
            } else {
                proxy.scrollTo(focusedFileID, anchor: .top)
            }
        }
    }
}

private struct GitDiffFileSection: View {
    let fileDiff: GitFileDiff

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            Divider()
            DiffContentView(
                diffResult: fileDiff.diffResult,
                baseURL: fileDiff.file.url.deletingLastPathComponent()
            )
        }
        .background(appColors?.panel ?? Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(appColors?.border ?? Color.secondary.opacity(0.24), lineWidth: 1)
        )
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var fileHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(fileDiff.file.relativePath)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            Text("+\(fileDiff.diffResult.addedCount)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            Text("-\(fileDiff.diffResult.removedCount)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)

            Text(fileDiff.file.status.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
    }
}
