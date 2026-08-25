import SwiftUI

enum ShellChromeMetrics {
    static let headerHeight: CGFloat = 40
}

@MainActor
struct MainContainerView: View {
    var tabs: TabCollection
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var snippetStore: PromptSnippetStore
    var projectStore: ProjectStore
    var gitRepositoryStatus: GitRepositoryStatus
    var searchCommandCenter: SidebarSearchCommandCenter
    var onSelectProject: (Project) -> Void
    var onSelectUnscoped: () -> Void
    var onProjectUpdated: (Project) -> Void
    var onProjectDeleted: (Project) -> Void
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void
    var onConfigurationSaved: () -> Void
    var onDirectoryChanged: (URL) -> Void

    @State private var projectSidebarController: ProjectSidebarController
    @State private var isShowingNewTabChooser = false
    @AppStorage("isLeftSidebarVisible") private var isLeftSidebarVisible = true
    @AppStorage("leftSidebarWidth") private var leftSidebarWidth: Double = 260
    @AppStorage("rightSidebarWidth") private var rightSidebarWidth: Double = 420
    @State private var pendingLeftSidebarWidth: Double?
    @State private var pendingRightSidebarWidth: Double?
    @State private var isHoveringLeftSidebarResizeHandle = false
    @State private var isDraggingLeftSidebarResizeHandle = false
    @State private var isHoveringSidebarResizeHandle = false
    @State private var isDraggingSidebarResizeHandle = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    private let sidebarResizeHandleHitWidth: Double = 8
    private let sidebarResizeHandleVisibleWidth: Double = 4

    init(
        tabs: TabCollection,
        scanner: DirectoryScanner,
        recentStore: RecentDocumentStore,
        snippetStore: PromptSnippetStore,
        projectStore: ProjectStore,
        gitRepositoryStatus: GitRepositoryStatus,
        searchCommandCenter: SidebarSearchCommandCenter,
        onSelectProject: @escaping (Project) -> Void,
        onSelectUnscoped: @escaping () -> Void = {},
        onProjectUpdated: @escaping (Project) -> Void = { _ in },
        onProjectDeleted: @escaping (Project) -> Void = { _ in },
        onOpenFile: @escaping () -> Void,
        onDocumentChanged: @escaping () -> Void,
        onConfigurationSaved: @escaping () -> Void = {},
        onDirectoryChanged: @escaping (URL) -> Void = { _ in }
    ) {
        self.tabs = tabs
        self.scanner = scanner
        self.recentStore = recentStore
        self.snippetStore = snippetStore
        self.projectStore = projectStore
        self.gitRepositoryStatus = gitRepositoryStatus
        self.searchCommandCenter = searchCommandCenter
        self.onSelectProject = onSelectProject
        self.onSelectUnscoped = onSelectUnscoped
        self.onProjectUpdated = onProjectUpdated
        self.onProjectDeleted = onProjectDeleted
        self.onOpenFile = onOpenFile
        self.onDocumentChanged = onDocumentChanged
        self.onConfigurationSaved = onConfigurationSaved
        self.onDirectoryChanged = onDirectoryChanged
        _projectSidebarController = State(
            initialValue: ProjectSidebarController(
                projectStore: projectStore,
                onSelectProject: onSelectProject,
                onSelectUnscoped: onSelectUnscoped,
                onProjectUpdated: onProjectUpdated,
                onProjectDeleted: onProjectDeleted
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let allocation = ShellWidthAllocator.allocate(
                containerWidth: geometry.size.width,
                requestedLeftWidth: pendingLeftSidebarWidth ?? leftSidebarWidth,
                requestedRightWidth: pendingRightSidebarWidth ?? rightSidebarWidth,
                wantsLeft: isLeftSidebarVisible,
                wantsRight: activeTabGroup?.rightUtilityRoute.isVisible ?? false
            )

            shell(allocation: allocation, size: geometry.size)
        }
        .sheet(isPresented: $isShowingNewTabChooser) {
            NewTabChooserView(
                onCreateTerminal: {
                    createTerminalTab()
                    isShowingNewTabChooser = false
                },
                onCreateMarkdown: {
                    createMarkdownTab()
                    isShowingNewTabChooser = false
                },
                onCancel: {
                    isShowingNewTabChooser = false
                }
            )
        }
        .onAppear {
            syncDirectoryToActiveTab()
            scanner.reload()
            activeGitDiffState?.refresh(for: scanner.currentDirectory)
            onDirectoryChanged(scanner.currentDirectory)
            setupActiveTabDirectoryObserver()
        }
        .onChange(of: tabs.activeTabID) { _, _ in
            syncDirectoryToActiveTab()
            activeGitDiffState?.refresh(for: scanner.currentDirectory)
            onDirectoryChanged(scanner.currentDirectory)
            setupActiveTabDirectoryObserver()
            onDocumentChanged()
        }
        .onChange(of: tabs.activeWorkspaceID) { _, _ in
            syncDirectoryToActiveTab()
            activeGitDiffState?.refresh(for: scanner.currentDirectory)
            onDirectoryChanged(scanner.currentDirectory)
            setupActiveTabDirectoryObserver()
            onDocumentChanged()
        }
        .onChange(of: scanner.currentDirectory) { _, directory in
            activeGitDiffState?.refresh(for: directory)
            onDirectoryChanged(directory)
        }
        .onChange(of: activeGitDiffState?.repositoryRoot?.path) { _, _ in
            activeTabGroup?.syncTimelineToGitRepository()
        }
        .onChange(of: activeGitDiffState?.isRefreshing) { _, isRefreshing in
            if isRefreshing == false {
                activeTabGroup?.syncTimelineToGitRepository()
            }
        }
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .tint(appColors?.accent ?? Color.accentColor)
    }

    private func shell(allocation: ShellWidthAllocation, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if let leftWidth = allocation.leftWidth {
                    ProjectSidebar(
                        projectStore: projectStore,
                        controller: projectSidebarController,
                        activeWorkspaceID: tabs.activeWorkspaceID,
                        width: leftWidth,
                        onHide: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isLeftSidebarVisible = false
                            }
                        }
                    )
                }

                VStack(spacing: 0) {
                    TabBarView(
                        tabs: tabs,
                        onNewTab: { isShowingNewTabChooser = true },
                        showsLeftSidebarToggle: allocation.leftWidth == nil,
                        onToggleLeftSidebar: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isLeftSidebarVisible = true
                            }
                        },
                        showsRightSidebarToggle: isRightSidebarAbsent(allocation.right),
                        onToggleRightSidebar: {
                            activeTabGroup?.toggleRightUtility()
                        }
                    )

                    ActiveTabContentView(
                        tabs: tabs,
                        onOpenFile: onOpenFile,
                        onNewTab: { isShowingNewTabChooser = true },
                        onDocumentChanged: onDocumentChanged,
                        onConfigurationSaved: onConfigurationSaved,
                        mentionedGitFileIDs: openMarkdownMentionedGitFileIDs,
                        onSearchShortcut: showFileBrowserSearch,
                        onSnippetShortcut: saveSnippetFromTerminalSelection
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 0)
                .frame(width: allocation.centerWidth)
                .frame(maxHeight: .infinity)

                if let group = activeTabGroup {
                    RightSidebarView(
                        selectedTab: group.rightUtilityRoute.selectedTab,
                        presentation: allocation.right,
                        onSelectTab: group.selectRightUtility,
                        gitRepositoryStatus: gitRepositoryStatus,
                        onCollapse: group.toggleRightUtility,
                        gitMode: group.gitUtilityMode,
                        onSelectGitMode: group.selectGitUtilityMode,
                        gitHistoryStore: group.gitHistoryStore,
                        repositoryRoot: group.gitDiffState.repositoryRoot,
                        gitDiffState: group.gitDiffState,
                        isGitDiffTabOpen: isGitDiffTabOpen,
                        onOpenGitFileInTab: openGitDiffFile,
                        onFocusGitFileInTab: focusGitDiffFile,
                        mentionedFileIDs: openMarkdownMentionedGitFileIDs,
                        snippetStore: snippetStore,
                        timelineStore: group.timelineStore,
                        scanner: scanner,
                        recentStore: recentStore,
                        currentFileURL: tabs.activeMarkdownTab?.fileURL,
                        onOpenMarkdown: openMarkdownFromSidebar,
                        onOpenOtherFile: openFileFromSidebar,
                        searchCommandCenter: searchCommandCenter
                    )
                    .id(group.id.rawValue)
                }
            }

            if let leftWidth = allocation.leftWidth {
                sidebarResizeHandle(
                    isHovering: isHoveringLeftSidebarResizeHandle,
                    isDragging: isDraggingLeftSidebarResizeHandle,
                    visibleAlignment: .trailing,
                    onHoverChanged: { isHoveringLeftSidebarResizeHandle = $0 },
                    onDragChanged: { pointerX in
                        isDraggingLeftSidebarResizeHandle = true
                        pendingLeftSidebarWidth = max(
                            ShellWidthAllocator.minimumLeftWidth,
                            min(pointerX + sidebarResizeHandleVisibleWidth / 2, 800)
                        )
                    },
                    onDragEnded: commitLeftSidebarResize
                )
                .position(
                    x: leftWidth - sidebarResizeHandleHitWidth / 2,
                    y: size.height / 2
                )
                .zIndex(10)
            }

            if let rightWidth = expandedWidth(allocation.right) {
                sidebarResizeHandle(
                    isHovering: isHoveringSidebarResizeHandle,
                    isDragging: isDraggingSidebarResizeHandle,
                    visibleAlignment: .leading,
                    onHoverChanged: { isHoveringSidebarResizeHandle = $0 },
                    onDragChanged: { pointerX in
                        isDraggingSidebarResizeHandle = true
                        pendingRightSidebarWidth = max(
                            ShellWidthAllocator.minimumRightWidth,
                            min(size.width - pointerX + sidebarResizeHandleVisibleWidth / 2, 800)
                        )
                    },
                    onDragEnded: commitRightSidebarResize
                )
                .position(
                    x: size.width - rightWidth + sidebarResizeHandleHitWidth / 2,
                    y: size.height / 2
                )
                .zIndex(10)
            }
        }
        .coordinateSpace(name: "main-container")
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var activeTabGroup: TabGroupState? {
        tabs.activeTabGroup
    }

    private var activeGitDiffState: GitDiffState? {
        activeTabGroup?.gitDiffState
    }

    private var openMarkdownMentionedGitFileIDs: Set<GitChangedFile.ID> {
        let markdown = tabs.tabs
            .compactMap { tab -> String? in
                guard let markdownTab = tab as? MarkdownTab,
                      markdownTab.groupState?.id == activeTabGroup?.id
                else { return nil }
                return markdownTab.state.document.editableContent
            }
            .joined(separator: "\n")
        return MarkdownGitReferenceIndex.mentionedFileIDs(
            in: String(markdown),
            changedFiles: activeGitDiffState?.changedFiles ?? []
        )
    }

    private var isGitDiffTabOpen: Bool {
        tabs.tabs.contains { tab in
            guard let gitDiffTab = tab as? GitDiffTab else { return false }
            return gitDiffTab.groupState?.id == activeTabGroup?.id
        }
    }

    private func expandedWidth(_ presentation: RightUtilityPresentation) -> Double? {
        guard case .expanded(let width) = presentation else { return nil }
        return width
    }

    private func isRightSidebarAbsent(_ presentation: RightUtilityPresentation) -> Bool {
        if case .hidden = presentation { return true }
        return false
    }

    private func commitLeftSidebarResize() {
        if let pendingLeftSidebarWidth {
            leftSidebarWidth = pendingLeftSidebarWidth
        }
        pendingLeftSidebarWidth = nil
        isDraggingLeftSidebarResizeHandle = false
    }

    private func commitRightSidebarResize() {
        if let pendingRightSidebarWidth {
            rightSidebarWidth = pendingRightSidebarWidth
        }
        pendingRightSidebarWidth = nil
        isDraggingSidebarResizeHandle = false
    }

    private func sidebarResizeHandle(
        isHovering: Bool,
        isDragging: Bool,
        visibleAlignment: Alignment,
        onHoverChanged: @escaping (Bool) -> Void,
        onDragChanged: @escaping (Double) -> Void,
        onDragEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: sidebarResizeHandleHitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(sidebarResizeHandleColor(isHovering: isHovering, isDragging: isDragging))
            .overlay(alignment: visibleAlignment) {
                Rectangle()
                    .fill(sidebarResizeHandleVisibleColor(isHovering: isHovering, isDragging: isDragging))
                    .frame(width: sidebarResizeHandleVisibleWidth)
            }
            .onHover { hovering in
                onHoverChanged(hovering)
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("main-container"))
                    .onChanged { value in onDragChanged(value.location.x) }
                    .onEnded { _ in onDragEnded() }
            )
    }

    private func sidebarResizeHandleColor(isHovering: Bool, isDragging: Bool) -> Color {
        if isDragging {
            return (appColors?.accent ?? Color.accentColor).opacity(0.18)
        }
        if isHovering {
            return (appColors?.accent ?? Color.accentColor).opacity(0.10)
        }
        return Color.clear
    }

    private func sidebarResizeHandleVisibleColor(isHovering: Bool, isDragging: Bool) -> Color {
        if isHovering || isDragging {
            return appColors?.accent ?? Color.accentColor
        }
        return appColors?.border ?? Color.secondary.opacity(0.35)
    }

    private func createTerminalTab() {
        let tab = tabs.createTerminalTab(
            workingDirectory: scanner.currentDirectory,
            onDirectoryChanged: { url in
                guard self.tabs.activeTerminalTab?.state.workingDirectory == url else { return }
                self.scanner.setDirectory(url)
            }
        )
        tab.groupState.recordTimeline(.terminalCreated(directory: scanner.currentDirectory))
    }

    private func createMarkdownTab() {
        tabs.createMarkdownTab(fileURL: nil)
    }

    private func showFileBrowserSearch(_ mode: SidebarSearchMode) {
        activeTabGroup?.showFileBrowserSearch(mode, commandCenter: searchCommandCenter)
    }

    private func saveSnippetFromTerminalSelection(_ body: String) {
        _ = snippetStore.add(body: body)
        activeTabGroup?.showSnippetsSidebar()
    }

    private func openMarkdownFromSidebar(_ url: URL) {
        openFileFromSidebar(url)
    }

    private func openFileFromSidebar(_ url: URL) {
        tabs.createMarkdownTab(fileURL: url)
        recentStore.record(url: url)
        scanner.setDirectory(url.deletingLastPathComponent())
        activeTabGroup?.recordTimeline(.markdownOpened(url: url))
        onDocumentChanged()
    }

    private func openGitDiffFile(_ file: GitChangedFile) {
        let tab = tabs.showGitDiffTabForActiveGroup()
        tab.state.focus(file)
        tab.groupState?.recordTimeline(.gitDiffFocused(relativePath: file.relativePath))
        onDocumentChanged()
    }

    private func focusGitDiffFile(_ file: GitChangedFile) {
        guard let groupID = activeTabGroup?.id,
              let tab = tabs.tabs.compactMap({ $0 as? GitDiffTab }).first(where: { $0.groupState?.id == groupID })
        else { return }
        tab.state.focus(file)
        tabs.selectTab(id: tab.id)
        tab.groupState?.recordTimeline(.gitDiffFocused(relativePath: file.relativePath))
        onDocumentChanged()
    }

    private func syncDirectoryToActiveTab() {
        if let terminalTab = tabs.activeTerminalTab {
            scanner.setDirectory(terminalTab.state.workingDirectory)
        } else if let markdownTab = tabs.activeMarkdownTab,
                  let fileURL = markdownTab.fileURL {
            scanner.setDirectory(fileURL.deletingLastPathComponent())
        } else if let directory = tabs.activeWorkingDirectory {
            scanner.setDirectory(directory)
        }
    }

    private func setupActiveTabDirectoryObserver() {
        guard let terminalTab = tabs.activeTerminalTab else { return }
        terminalTab.state.onDirectoryChanged = { url in
            terminalTab.groupState.updateWorkingDirectory(url)
            guard self.tabs.activeTerminalTab?.id == terminalTab.id else { return }
            self.scanner.setDirectory(url)
        }
    }
}
