import SwiftUI

struct MainContainerView: View {
    var tabs: TabCollection
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var snippetStore: PromptSnippetStore
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void
    var onConfigurationSaved: () -> Void = {}
    var onDirectoryChanged: (URL) -> Void = { _ in }

    @State private var isShowingNewTabChooser = false
    @State private var gitDiffState = GitDiffState()
    @AppStorage("isLeftSidebarVisible") private var isLeftSidebarVisible = true
    @AppStorage("leftSidebarWidth") private var leftSidebarWidth: Double = 260
    @AppStorage("rightSidebarWidth") private var rightSidebarWidth: Double = 420
    @State private var isHoveringLeftSidebarResizeHandle = false
    @State private var isDraggingLeftSidebarResizeHandle = false
    @State private var isHoveringSidebarResizeHandle = false
    @State private var isDraggingSidebarResizeHandle = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
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
                isDiffEnabled: gitDiffState.isInGitRepository,
                isDiffVisible: gitDiffState.isShowingSidebar,
                onToggleDiff: {
                    gitDiffState.toggleSidebar(for: scanner.currentDirectory)
                }
            )
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if isLeftSidebarVisible {
                        FileBrowserSidebar(
                            scanner: scanner,
                            recentStore: recentStore,
                            currentFileURL: tabs.activeMarkdownTab?.fileURL,
                            onOpenMarkdown: openMarkdownFromSidebar,
                            onOpenOtherFile: openFileFromSidebar,
                            width: clampedLeftSidebarWidth(for: geometry.size.width)
                        )

                        sidebarResizeHandle(
                            currentWidth: leftSidebarWidth,
                            isHovering: isHoveringLeftSidebarResizeHandle,
                            isDragging: isDraggingLeftSidebarResizeHandle,
                            onHoverChanged: { isHoveringLeftSidebarResizeHandle = $0 },
                            onDragStarted: { isDraggingLeftSidebarResizeHandle = true },
                            onDragChanged: { proposedWidth in
                                leftSidebarWidth = clampedLeftSidebarWidth(for: geometry.size.width, proposedWidth: proposedWidth)
                            },
                            onDragEnded: { isDraggingLeftSidebarResizeHandle = false },
                            dragDirection: .leading
                        )
                    }

                    ActiveTabContentView(
                        tabs: tabs,
                        onOpenFile: onOpenFile,
                        onNewTab: { isShowingNewTabChooser = true },
                        onDocumentChanged: onDocumentChanged,
                        onConfigurationSaved: onConfigurationSaved
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if gitDiffState.isShowingSidebar {
                        sidebarResizeHandle(
                            currentWidth: rightSidebarWidth,
                            isHovering: isHoveringSidebarResizeHandle,
                            isDragging: isDraggingSidebarResizeHandle,
                            onHoverChanged: { isHoveringSidebarResizeHandle = $0 },
                            onDragStarted: { isDraggingSidebarResizeHandle = true },
                            onDragChanged: { proposedWidth in
                                rightSidebarWidth = clampedSidebarWidth(for: geometry.size.width, proposedWidth: proposedWidth)
                            },
                            onDragEnded: { isDraggingSidebarResizeHandle = false },
                            dragDirection: .trailing
                        )
                        RightSidebarView(
                            gitDiffState: gitDiffState,
                            snippetStore: snippetStore,
                            width: clampedSidebarWidth(for: geometry.size.width),
                            onSelectFile: openGitDiffFile
                        )
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
            gitDiffState.refresh(for: scanner.currentDirectory)
            onDirectoryChanged(scanner.currentDirectory)
            setupActiveTabDirectoryObserver()
        }
        .onChange(of: tabs.activeTabID) { _, _ in
            syncDirectoryToActiveTab()
            gitDiffState.refresh(for: scanner.currentDirectory)
            onDirectoryChanged(scanner.currentDirectory)
            setupActiveTabDirectoryObserver()
            onDocumentChanged()
        }
        .onChange(of: scanner.currentDirectory) { _, directory in
            gitDiffState.refresh(for: directory)
            onDirectoryChanged(directory)
        }
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .tint(appColors?.accent ?? Color.accentColor)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private func sidebarResizeHandle(
        currentWidth: Double,
        isHovering: Bool,
        isDragging: Bool,
        onHoverChanged: @escaping (Bool) -> Void,
        onDragStarted: @escaping () -> Void,
        onDragChanged: @escaping (Double) -> Void,
        onDragEnded: @escaping () -> Void,
        dragDirection: SidebarResizeHandleDirection
    ) -> some View {
        SidebarResizeHandleView(
            currentWidth: currentWidth,
            dragDirection: dragDirection,
            onHoverChanged: onHoverChanged,
            onDragStarted: onDragStarted,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
        .frame(width: 6)
        .background(sidebarResizeHandleColor(isHovering: isHovering, isDragging: isDragging))
        .overlay(
            Rectangle()
                .fill(sidebarResizeHandleAccent)
                .frame(width: 2)
                .opacity((isHovering || isDragging) ? 1 : 0)
        )
    }

    private func sidebarResizeHandleColor(isHovering: Bool, isDragging: Bool) -> Color {
        if isDragging {
            return (appColors?.accent ?? Color.accentColor).opacity(0.18)
        }

        if isHovering {
            return (appColors?.accent ?? Color.accentColor).opacity(0.10)
        }

        return appColors?.border ?? Color.secondary.opacity(0.14)
    }

    private var sidebarResizeHandleAccent: Color {
        appColors?.accent ?? Color.accentColor
    }

    private func clampedSidebarWidth(for containerWidth: Double) -> Double {
        max(250, min(800, min(rightSidebarWidth, max(containerWidth - 120, 250))))
    }

    private func clampedLeftSidebarWidth(for containerWidth: Double) -> Double {
        max(220, min(520, min(leftSidebarWidth, max(containerWidth - 240, 220))))
    }

    private func clampedSidebarWidth(for containerWidth: Double, proposedWidth: Double) -> Double {
        return max(250, min(800, min(proposedWidth, max(containerWidth - 120, 250))))
    }

    private func clampedLeftSidebarWidth(for containerWidth: Double, proposedWidth: Double) -> Double {
        return max(220, min(520, min(proposedWidth, max(containerWidth - 240, 220))))
    }

    private func createTerminalTab() {
        tabs.createTerminalTab(
            workingDirectory: scanner.currentDirectory,
            onDirectoryChanged: { url in
                guard self.tabs.activeTerminalTab?.state.workingDirectory == url else { return }
                self.scanner.setDirectory(url)
            }
        )
    }
    
    private func createMarkdownTab() {
        tabs.createMarkdownTab(fileURL: nil)
    }
    
    private func openMarkdownFromSidebar(_ url: URL) {
        openFileFromSidebar(url)
    }

    private func openFileFromSidebar(_ url: URL) {
        tabs.createMarkdownTab(fileURL: url)
        recentStore.record(url: url)
        scanner.setDirectory(url.deletingLastPathComponent())
        onDocumentChanged()
    }

    private func openGitDiffFile(_ file: GitChangedFile) {
        tabs.showGitDiffTab(state: gitDiffState)
        gitDiffState.focus(file)
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
            guard self.tabs.activeTerminalTab?.id == terminalTab.id else { return }
            self.scanner.setDirectory(url)
        }
    }
}

private struct SidebarResizeHandleView: NSViewRepresentable {
    let currentWidth: Double
    let dragDirection: SidebarResizeHandleDirection
    let onHoverChanged: (Bool) -> Void
    let onDragStarted: () -> Void
    let onDragChanged: (Double) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> SidebarResizeHandleNSView {
        let view = SidebarResizeHandleNSView()
        view.currentSidebarWidth = currentWidth
        view.dragDirection = dragDirection
        view.onHoverChanged = onHoverChanged
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: SidebarResizeHandleNSView, context: Context) {
        nsView.currentSidebarWidth = currentWidth
        nsView.dragDirection = dragDirection
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragStarted = onDragStarted
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}

private final class SidebarResizeHandleNSView: NSView {
    var currentSidebarWidth: Double = 420
    var dragDirection: SidebarResizeHandleDirection = .trailing
    var onHoverChanged: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragChanged: ((Double) -> Void)?
    var onDragEnded: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var initialMouseXInWindow: CGFloat?
    private var initialSidebarWidth: CGFloat?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseXInWindow = event.locationInWindow.x
        initialSidebarWidth = currentSidebarWidth
        onDragStarted?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialMouseXInWindow, let initialSidebarWidth else { return }
        let deltaX = event.locationInWindow.x - initialMouseXInWindow
        let proposedWidth: CGFloat
        switch dragDirection {
        case .leading:
            proposedWidth = initialSidebarWidth + deltaX
        case .trailing:
            proposedWidth = initialSidebarWidth - deltaX
        }
        onDragChanged?(proposedWidth)
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseXInWindow = nil
        initialSidebarWidth = nil
        onDragEnded?()
    }
}

private enum SidebarResizeHandleDirection {
    case leading
    case trailing
}
