import SwiftUI

struct MainContainerView: View {
    var tabs: TabCollection
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var snippetStore: PromptSnippetStore
    var searchCommandCenter: SidebarSearchCommandCenter
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void
    var onConfigurationSaved: () -> Void = {}
    var onDirectoryChanged: (URL) -> Void = { _ in }

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
    
    var body: some View {
        VStack(spacing: 0) {
            TabBarView(
                tabs: tabs,
                onNewTab: { isShowingNewTabChooser = true },
                isLeftSidebarVisible: isLeftSidebarVisible,
                onToggleLeftSidebar: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isLeftSidebarVisible.toggle()
                    }
                },
                isDiffEnabled: activeGitDiffState?.isInGitRepository ?? false,
                isDiffVisible: activeGitDiffState?.isShowingSidebar ?? false,
                onToggleDiff: {
                    activeGitDiffState?.toggleSidebar(for: scanner.currentDirectory)
                }
            )
            
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        if isLeftSidebarVisible {
                            FileBrowserSidebar(
                                scanner: scanner,
                                recentStore: recentStore,
                                currentFileURL: tabs.activeMarkdownTab?.fileURL,
                                onOpenMarkdown: openMarkdownFromSidebar,
                                onOpenOtherFile: openFileFromSidebar,
                                width: currentLeftSidebarWidth(for: geometry.size.width),
                                searchCommandCenter: searchCommandCenter
                            )
                        }

                        ActiveTabContentView(
                            tabs: tabs,
                            onOpenFile: onOpenFile,
                            onNewTab: { isShowingNewTabChooser = true },
                            onDocumentChanged: onDocumentChanged,
                            onConfigurationSaved: onConfigurationSaved,
                            mentionedGitFileIDs: openMarkdownMentionedGitFileIDs,
                            onSearchShortcut: focusSidebarSearch,
                            onSnippetShortcut: saveSnippetFromTerminalSelection
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                        if let gitDiffState = activeGitDiffState,
                           let timelineStore = activeTimelineStore,
                           gitDiffState.isShowingSidebar {
                            RightSidebarView(
                                gitDiffState: gitDiffState,
                                snippetStore: snippetStore,
                                timelineStore: timelineStore,
                                width: currentRightSidebarWidth(for: geometry.size.width),
                                isGitDiffTabOpen: isGitDiffTabOpen,
                                onSelectFile: openGitDiffFile,
                                mentionedFileIDs: openMarkdownMentionedGitFileIDs,
                                selectedTab: activeRightSidebarTab
                            )
                            .id(tabs.activeTabGroup?.id.rawValue)
                        }
                    }

                    if isLeftSidebarVisible {
                        sidebarResizeHandle(
                            isHovering: isHoveringLeftSidebarResizeHandle,
                            isDragging: isDraggingLeftSidebarResizeHandle,
                            visibleAlignment: .trailing,
                            onHoverChanged: { isHoveringLeftSidebarResizeHandle = $0 },
                            onDragChanged: { pointerX in
                                isDraggingLeftSidebarResizeHandle = true
                                pendingLeftSidebarWidth = clampedLeftSidebarWidth(
                                    for: geometry.size.width,
                                    proposedWidth: pointerX + sidebarResizeHandleVisibleWidth / 2
                                )
                            },
                            onDragEnded: {
                                if let pendingLeftSidebarWidth {
                                    leftSidebarWidth = pendingLeftSidebarWidth
                                }
                                pendingLeftSidebarWidth = nil
                                isDraggingLeftSidebarResizeHandle = false
                            }
                        )
                        .position(
                            x: currentLeftSidebarWidth(for: geometry.size.width) - sidebarResizeHandleHitWidth / 2,
                            y: geometry.size.height / 2
                        )
                        .zIndex(10)
                    }

                    if activeGitDiffState?.isShowingSidebar == true {
                        sidebarResizeHandle(
                            isHovering: isHoveringSidebarResizeHandle,
                            isDragging: isDraggingSidebarResizeHandle,
                            visibleAlignment: .leading,
                            onHoverChanged: { isHoveringSidebarResizeHandle = $0 },
                            onDragChanged: { pointerX in
                                isDraggingSidebarResizeHandle = true
                                pendingRightSidebarWidth = clampedSidebarWidth(
                                    for: geometry.size.width,
                                    proposedWidth: geometry.size.width - pointerX + sidebarResizeHandleVisibleWidth / 2
                                )
                            },
                            onDragEnded: {
                                if let pendingRightSidebarWidth {
                                    rightSidebarWidth = pendingRightSidebarWidth
                                }
                                pendingRightSidebarWidth = nil
                                isDraggingSidebarResizeHandle = false
                            }
                        )
                        .position(
                            x: geometry.size.width - currentRightSidebarWidth(for: geometry.size.width) + sidebarResizeHandleHitWidth / 2,
                            y: geometry.size.height / 2
                        )
                        .zIndex(10)
                    }
                }
                .coordinateSpace(name: "main-container")
            }
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
        .onChange(of: scanner.currentDirectory) { _, directory in
            activeGitDiffState?.refresh(for: directory)
            onDirectoryChanged(directory)
        }
        .onChange(of: activeGitDiffState?.repositoryRoot?.path) { _, _ in
            tabs.activeTabGroup?.syncTimelineToGitRepository()
        }
        .onChange(of: activeGitDiffState?.isRefreshing) { _, isRefreshing in
            if isRefreshing == false {
                tabs.activeTabGroup?.syncTimelineToGitRepository()
            }
        }
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .tint(appColors?.accent ?? Color.accentColor)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var openMarkdownMentionedGitFileIDs: Set<GitChangedFile.ID> {
        let markdown = tabs.tabs
            .compactMap { tab -> String? in
                guard let markdownTab = tab as? MarkdownTab,
                      markdownTab.groupState?.id == tabs.activeTabGroup?.id
                else { return nil }
                return markdownTab.state.document.editableContent
            }
            .joined(separator: "\n")
        return MarkdownGitReferenceIndex.mentionedFileIDs(in: String(markdown), changedFiles: activeGitDiffState?.changedFiles ?? [])
    }

    private var isGitDiffTabOpen: Bool {
        tabs.tabs.contains { tab in
            guard let gitDiffTab = tab as? GitDiffTab else { return false }
            return gitDiffTab.groupState?.id == tabs.activeTabGroup?.id
        }
    }

    private var activeGitDiffState: GitDiffState? {
        tabs.activeTabGroup?.gitDiffState
    }

    private var activeTimelineStore: AgentTimelineStore? {
        tabs.activeTabGroup?.timelineStore
    }

    private var activeRightSidebarTab: Binding<RightSidebarTab> {
        Binding(
            get: { tabs.activeTabGroup?.rightSidebarTab ?? .gitChanges },
            set: { newValue in
                tabs.activeTabGroup?.rightSidebarTab = newValue
            }
        )
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
                .onChanged { value in
                    onDragChanged(value.location.x)
                }
                .onEnded { _ in
                    onDragEnded()
                }
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

    private var sidebarResizeHandleAccent: Color {
        appColors?.accent ?? Color.accentColor
    }

    private func sidebarResizeHandleVisibleColor(isHovering: Bool, isDragging: Bool) -> Color {
        if isHovering || isDragging {
            return sidebarResizeHandleAccent
        }

        return appColors?.border ?? Color.secondary.opacity(0.35)
    }

    private func currentRightSidebarWidth(for containerWidth: Double) -> Double {
        clampedSidebarWidth(for: containerWidth, proposedWidth: pendingRightSidebarWidth ?? rightSidebarWidth)
    }

    private func currentLeftSidebarWidth(for containerWidth: Double) -> Double {
        clampedLeftSidebarWidth(for: containerWidth, proposedWidth: pendingLeftSidebarWidth ?? leftSidebarWidth)
    }

    private func clampedSidebarWidth(for containerWidth: Double, proposedWidth: Double) -> Double {
        return max(250, min(800, min(proposedWidth, max(containerWidth - 120, 250))))
    }

    private func clampedLeftSidebarWidth(for containerWidth: Double, proposedWidth: Double) -> Double {
        return max(220, min(proposedWidth, leftSidebarMaxWidth(for: containerWidth)))
    }

    private func leftSidebarMaxWidth(for containerWidth: Double) -> Double {
        max(220, containerWidth * 0.5)
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

    private func focusSidebarSearch(_ mode: SidebarSearchMode) {
        isLeftSidebarVisible = true
        searchCommandCenter.focus(mode)
    }

    private func saveSnippetFromTerminalSelection(_ body: String) {
        _ = snippetStore.add(body: body)
        tabs.activeTabGroup?.showSnippetsSidebar()
    }
    
    private func openMarkdownFromSidebar(_ url: URL) {
        openFileFromSidebar(url)
    }

    private func openFileFromSidebar(_ url: URL) {
        tabs.createMarkdownTab(fileURL: url)
        recentStore.record(url: url)
        scanner.setDirectory(url.deletingLastPathComponent())
        tabs.activeTabGroup?.recordTimeline(.markdownOpened(url: url))
        onDocumentChanged()
    }

    private func openGitDiffFile(_ file: GitChangedFile) {
        let tab = tabs.showGitDiffTabForActiveGroup()
        tab.state.focus(file)
        tab.groupState?.recordTimeline(.gitDiffFocused(relativePath: file.relativePath))
        onDocumentChanged()
    }

    private func syncDirectoryToActiveTab() {
        if let terminalTab = tabs.activeTerminalTab {
            scanner.setDirectory(terminalTab.state.workingDirectory)
        } else if let markdownTab = tabs.activeMarkdownTab,
                  let fileURL = markdownTab.fileURL {
            scanner.setDirectory(fileURL.deletingLastPathComponent())
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
