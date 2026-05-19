import SwiftUI
import AppKit
import GhosttyTerminal

struct MainContainerView: View {
    var tabs: TabCollection
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var onOpenFile: () -> Void
    var onDocumentChanged: () -> Void

    @State private var isShowingNewTabChooser = false
    
    var body: some View {
        VStack(spacing: 0) {
            TabBarView(
                tabs: tabs,
                onNewTab: { isShowingNewTabChooser = true }
            )
            
            HStack(spacing: 0) {
                FileBrowserSidebar(
                    scanner: scanner,
                    recentStore: recentStore,
                    currentFileURL: tabs.activeMarkdownTab?.fileURL,
                    onOpenMarkdown: openMarkdownFromSidebar,
                    onOpenOtherFile: { _ in },
                    onEnterDirectory: handleEnterDirectory
                )
                
                Divider()
                
                ActiveTabContentView(
                    tabs: tabs,
                    onOpenFile: onOpenFile,
                    onNewTab: { isShowingNewTabChooser = true },
                    onDocumentChanged: onDocumentChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            setupActiveTabDirectoryObserver()
        }
        .onChange(of: tabs.activeTabID) { _, _ in
            syncDirectoryToActiveTab()
            setupActiveTabDirectoryObserver()
            onDocumentChanged()
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
        tabs.createMarkdownTab(fileURL: url)
        recentStore.record(url: url)
        scanner.setDirectory(url.deletingLastPathComponent())
        onDocumentChanged()
    }

    private func handleEnterDirectory(_ url: URL) {
        if let terminalTab = tabs.activeTerminalTab,
           let terminalView = terminalTab.state.terminalView {
            let path = url.path
            terminalView.sendText("cd \(path)")
            sendEnterKey(to: terminalView)
        } else {
            scanner.enterDirectory(url)
        }
    }
    
    private func sendEnterKey(to terminalView: AppTerminalView) {
        let enterKeyCode: UInt16 = 36
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: terminalView.window?.windowNumber ?? 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: enterKeyCode
        ) else { return }
        
        NSApp.postEvent(event, atStart: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
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
