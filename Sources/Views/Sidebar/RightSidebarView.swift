import SwiftUI

struct RightSidebarView: View {
    var gitDiffState: GitDiffState
    var snippetStore: PromptSnippetStore
    var width: Double
    var onSelectFile: (GitChangedFile) -> Void

    @State private var selectedTab: RightSidebarTab = .gitChanges
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(appColors?.panel ?? Color(NSColor.controlBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .onChange(of: gitDiffState.repositoryRoot) { _, newRoot in
            if newRoot == nil && selectedTab == .gitChanges {
                selectedTab = .snippets
            }
        }
        .onAppear {
            if gitDiffState.repositoryRoot == nil && selectedTab == .gitChanges {
                selectedTab = .snippets
            }
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: selectedTab.systemImage)
                    .foregroundStyle(.secondary)
                Text("작업 사이드바")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                gitRefreshControls
            }

            Picker("", selection: $selectedTab) {
                ForEach(RightSidebarTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var gitRefreshControls: some View {
        if selectedTab == .gitChanges {
            if gitDiffState.isRefreshing {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 14, height: 14)
            }
            Button {
                if let root = gitDiffState.repositoryRoot {
                    gitDiffState.refresh(for: root)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(String(localized: "새로고침"))
            .disabled(gitDiffState.isRefreshing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .gitChanges:
            GitChangesSidebar(
                state: gitDiffState,
                onSelectFile: onSelectFile
            )
        case .snippets:
            PromptSnippetsSidebarView(store: snippetStore)
        }
    }
}

private enum RightSidebarTab: String, CaseIterable, Identifiable {
    case gitChanges
    case snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gitChanges:
            return String(localized: "Git 변경 파일")
        case .snippets:
            return String(localized: "스니펫")
        }
    }

    var systemImage: String {
        switch self {
        case .gitChanges:
            return "arrow.left.arrow.right.circle"
        case .snippets:
            return "text.quote"
        }
    }
}
