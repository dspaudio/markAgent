import SwiftUI

struct RightSidebarView: View {
    var selectedTab: RightSidebarTab
    var presentation: RightUtilityPresentation
    var onSelectTab: (RightSidebarTab) -> Void
    var gitRepositoryStatus: GitRepositoryStatus
    var onCollapse: () -> Void

    var gitMode: GitUtilityMode
    var onSelectGitMode: (GitUtilityMode) -> Void
    var gitHistoryStore: GitHistoryStore
    var repositoryRoot: URL?
    var gitDiffState: GitDiffState
    var isGitDiffTabOpen: Bool
    var onOpenGitFileInTab: (GitChangedFile) -> Void
    var onFocusGitFileInTab: (GitChangedFile) -> Void
    var mentionedFileIDs: Set<GitChangedFile.ID> = []

    var snippetStore: PromptSnippetStore
    var timelineStore: AgentTimelineStore

    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenMarkdown: (URL) -> Void
    var onOpenOtherFile: (URL) -> Void
    var searchCommandCenter: SidebarSearchCommandCenter?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        presentationContent
            .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(appColors?.foreground ?? Color.primary)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    @ViewBuilder
    private var presentationContent: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .railOnly(let width):
            HStack(spacing: 0) {
                collapseButton
            }
            .frame(width: width, height: ShellChromeMetrics.headerHeight)
            .frame(maxHeight: .infinity, alignment: .top)
        case .expanded(let width):
            VStack(spacing: 0) {
                utilityHeader
                Divider()

                TitlebarGitBranchView(status: gitRepositoryStatus)
                    .padding(.horizontal, 8)
                    .frame(height: 32)

                Divider()

                GeometryReader { geometry in
                    selectedBody(width: geometry.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var utilityHeader: some View {
        HStack(spacing: 0) {
            ForEach(RightSidebarTab.allCases) { tab in
                utilityButton(tab)
            }

            Spacer(minLength: 0)
            collapseButton
        }
        .padding(.horizontal, 4)
        .frame(height: ShellChromeMetrics.headerHeight)
    }

    private var collapseButton: some View {
        Button(action: onCollapse) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain)
        .help(String(localized: "오른쪽 사이드바 숨기기"))
        .accessibilityIdentifier("sidebar.right")
    }

    private func utilityButton(_ tab: RightSidebarTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            onSelectTab(tab)
        } label: {
            Image(systemName: tab.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: ShellChromeMetrics.headerHeight)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? (appColors?.accent ?? Color.accentColor) : Color.clear)
                        .frame(width: 18, height: 2)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? (appColors?.accent ?? Color.accentColor) : Color.secondary)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    @ViewBuilder
    private func selectedBody(width: Double) -> some View {
        switch selectedTab {
        case .snippets:
            PromptSnippetsSidebarView(store: snippetStore)
        case .timeline:
            AgentTimelineSidebarView(store: timelineStore)
        case .gitHistory:
            GitUtilitySidebarView(
                mode: gitMode,
                onSelectMode: onSelectGitMode,
                historyStore: gitHistoryStore,
                repositoryRoot: repositoryRoot,
                gitDiffState: gitDiffState,
                isGitDiffTabOpen: isGitDiffTabOpen,
                onOpenFileInTab: onOpenGitFileInTab,
                onFocusFileInTab: onFocusGitFileInTab,
                mentionedFileIDs: mentionedFileIDs
            )
        case .fileBrowser:
            FileBrowserSidebar(
                scanner: scanner,
                recentStore: recentStore,
                currentFileURL: currentFileURL,
                onOpenMarkdown: onOpenMarkdown,
                onOpenOtherFile: onOpenOtherFile,
                width: width,
                searchCommandCenter: searchCommandCenter
            )
        }
    }
}
