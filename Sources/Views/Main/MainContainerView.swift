import SwiftUI

struct MainContainerView: View {
    var tabs: TabCollection
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void

    @State private var isShowingNewTabChooser = false
    @State private var gitDiffState = GitDiffState()
    
    var body: some View {
        VStack(spacing: 0) {
            TabBarView(
                tabs: tabs,
                onNewTab: { isShowingNewTabChooser = true },
                isDiffEnabled: gitDiffState.isInGitRepository,
                isDiffVisible: gitDiffState.isShowingSidebar,
                onToggleDiff: {
                    gitDiffState.toggleSidebar(for: scanner.currentDirectory)
                }
            )
            
            HStack(spacing: 0) {
                FileBrowserSidebar(
                    scanner: scanner,
                    recentStore: recentStore,
                    currentFileURL: tabs.activeMarkdownTab?.fileURL,
                    onOpenMarkdown: openMarkdownFromSidebar,
                    onOpenOtherFile: openFileFromSidebar
                )
                
                Divider()
                
                ActiveTabContentView(
                    tabs: tabs,
                    onOpenFile: onOpenFile,
                    onNewTab: { isShowingNewTabChooser = true },
                    onDocumentChanged: onDocumentChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if gitDiffState.isShowingSidebar {
                    Divider()

                    GitChangesSidebar(state: gitDiffState)
                }
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
            setupActiveTabDirectoryObserver()
        }
        .onChange(of: tabs.activeTabID) { _, _ in
            syncDirectoryToActiveTab()
            gitDiffState.refresh(for: scanner.currentDirectory)
            setupActiveTabDirectoryObserver()
            onDocumentChanged()
        }
        .onChange(of: scanner.currentDirectory) { _, directory in
            gitDiffState.refresh(for: directory)
        }
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
