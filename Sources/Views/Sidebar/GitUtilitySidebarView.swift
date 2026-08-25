import SwiftUI

struct GitUtilitySidebarView: View {
    var mode: GitUtilityMode
    var onSelectMode: (GitUtilityMode) -> Void

    var historyStore: GitHistoryStore
    var repositoryRoot: URL?

    var gitDiffState: GitDiffState
    var isGitDiffTabOpen: Bool
    var onOpenFileInTab: (GitChangedFile) -> Void
    var onFocusFileInTab: (GitChangedFile) -> Void
    var mentionedFileIDs: Set<GitChangedFile.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            activeBody
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                modeButton(.history, title: String(localized: "히스토리"), identifier: "git-utility-mode-history")
                modeButton(.changes, title: String(localized: "변경 사항"), identifier: "git-utility-mode-changes")
            }

            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 14, height: 14)
            }

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "새로고침"))
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func modeButton(
        _ candidate: GitUtilityMode,
        title: String,
        identifier: String
    ) -> some View {
        Button(title) {
            onSelectMode(candidate)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(mode == candidate ? Color.accentColor : nil)
        .accessibilityIdentifier(identifier)
    }

    private var isRefreshing: Bool {
        switch mode {
        case .history:
            return historyStore.state == .loading
        case .changes:
            return gitDiffState.isRefreshing
        }
    }

    private func refresh() {
        switch mode {
        case .history:
            Task {
                await historyStore.refresh(repositoryRoot: repositoryRoot)
            }
        case .changes:
            if let repositoryRoot = gitDiffState.repositoryRoot {
                gitDiffState.refresh(for: repositoryRoot)
            }
        }
    }

    @ViewBuilder
    private var activeBody: some View {
        switch mode {
        case .history:
            GitHistorySidebarView(
                store: historyStore,
                repositoryRoot: repositoryRoot
            )
        case .changes:
            GitChangesSidebar(
                state: gitDiffState,
                isGitDiffTabOpen: isGitDiffTabOpen,
                onOpenFileInTab: onOpenFileInTab,
                onFocusFileInTab: onFocusFileInTab,
                mentionedFileIDs: mentionedFileIDs
            )
        }
    }
}
