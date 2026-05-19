import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let tabs = TabCollection()
    let recentStore = RecentDocumentStore()
    let directoryScanner: DirectoryScanner
    let dirtyPrompter: AppDirtyDocumentPrompter
    var isAlwaysOnTop = true
    var window: NSWindow?

    private var isClosingAfterDirtyConfirmation = false
    private let windowFrameDefaultsKey = "MarkAgent.windowFrame"

    override init() {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        self.directoryScanner = DirectoryScanner(currentDirectory: homeURL)
        self.dirtyPrompter = AppDirtyDocumentPrompter(window: nil)
        super.init()
        tabs.dirtyPrompter = dirtyPrompter
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupWindow()
        tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        updateWindowTitle()
        NSRunningApplication.current.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func setupWindow() {
        let appTheme = GhosttyConfig.userConfig()?.colorTheme
        let contentView = MainContainerView(
            tabs: tabs,
            scanner: directoryScanner,
            recentStore: recentStore,
            onOpenFile: { [weak self] in
                self?.openFile()
            },
            onDocumentChanged: { [weak self] in
                self?.updateWindowTitle()
            }
        )
        .environment(\.terminalAppTheme, appTheme)
        .preferredColorScheme(appTheme?.preferredColorScheme)
        let hostingView = NSHostingView(rootView: contentView)

        let window = MarkAgentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .floating
        window.delegate = self
        self.window = window
        dirtyPrompter.window = window

        restoreWindowFrame(window)
        window.makeKeyAndOrderFront(nil)
        updateWindowTitle()
    }

    private func restoreWindowFrame(_ window: NSWindow) {
        if let savedFrame = savedWindowFrame(), isFrameVisible(savedFrame) {
            window.setFrame(savedFrame, display: true)
            return
        }

        positionWindowOnRight(window)
    }

    private func savedWindowFrame() -> NSRect? {
        let value = UserDefaults.standard.string(forKey: windowFrameDefaultsKey)
        guard let value else { return nil }

        let frame = NSRectFromString(value)
        guard !frame.isEmpty, frame.width >= 480, frame.height >= 320 else { return nil }
        return frame
    }

    private func isFrameVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            screen.visibleFrame.intersection(frame).width >= 160
                && screen.visibleFrame.intersection(frame).height >= 120
        }
    }

    private func saveWindowFrame(_ window: NSWindow?) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: windowFrameDefaultsKey)
    }

    private func positionWindowOnRight(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }
        let screenFrame = screen.visibleFrame
        let windowWidth = window.frame.width
        let windowHeight = window.frame.height
        let margin: CGFloat = 20
        let x = screenFrame.maxX - windowWidth - margin
        let y = screenFrame.midY - windowHeight / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(
            title: "About MarkAgent",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())

        let servicesMenuItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesMenuItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesMenuItem)

        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide MarkAgent", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MarkAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let newTerminalItem = NSMenuItem(title: "New Terminal Tab", action: #selector(newTab), keyEquivalent: "t")
        newTerminalItem.target = self
        fileMenu.addItem(newTerminalItem)

        let newMarkdownItem = NSMenuItem(title: "New Markdown Tab", action: #selector(newMarkdownTab), keyEquivalent: "n")
        newMarkdownItem.target = self
        fileMenu.addItem(newMarkdownItem)

        fileMenu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open…", action: #selector(openFile), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        fileMenu.addItem(.separator())

        let saveItem = NSMenuItem(title: "Save", action: #selector(saveDocument), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(saveItem)

        fileMenu.addItem(.separator())

        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let gotoTabItems: [(title: String, selector: Selector, key: String)] = [
            ("Select Tab 1", #selector(gotoTab1), "1"),
            ("Select Tab 2", #selector(gotoTab2), "2"),
            ("Select Tab 3", #selector(gotoTab3), "3"),
            ("Select Tab 4", #selector(gotoTab4), "4"),
            ("Select Tab 5", #selector(gotoTab5), "5"),
            ("Select Tab 6", #selector(gotoTab6), "6"),
            ("Select Tab 7", #selector(gotoTab7), "7"),
            ("Select Tab 8", #selector(gotoTab8), "8"),
            ("Select Tab 9", #selector(gotoTab9), "9"),
            ("Select Tab 10", #selector(gotoTab10), "0"),
        ]
        for item in gotoTabItems {
            let menuItem = NSMenuItem(title: item.title, action: item.selector, keyEquivalent: item.key)
            menuItem.target = self
            viewMenu.addItem(menuItem)
        }

        viewMenu.addItem(.separator())

        let toggleModeItem = NSMenuItem(title: "Preview", action: #selector(toggleViewMode), keyEquivalent: "p")
        toggleModeItem.keyEquivalentModifierMask = [.command, .control]
        toggleModeItem.target = self
        viewMenu.addItem(toggleModeItem)

        let rawViewItem = NSMenuItem(title: "Raw Edit", action: #selector(showRawView), keyEquivalent: "r")
        rawViewItem.keyEquivalentModifierMask = [.command, .control]
        rawViewItem.target = self
        viewMenu.addItem(rawViewItem)

        let toggleDiffItem = NSMenuItem(title: "Toggle Diff", action: #selector(toggleDiff), keyEquivalent: "d")
        toggleDiffItem.target = self
        viewMenu.addItem(toggleDiffItem)

        viewMenu.addItem(.separator())

        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "t")
        alwaysOnTopItem.keyEquivalentModifierMask = [.command, .shift]
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = .on
        viewMenu.addItem(alwaysOnTopItem)

        viewMenu.addItem(.separator())
        let enterFullScreenItem = NSMenuItem(title: "Enter Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        enterFullScreenItem.keyEquivalentModifierMask = [.command, .control]
        enterFullScreenItem.target = self
        viewMenu.addItem(enterFullScreenItem)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu
        let helpItem = NSMenuItem(title: "MarkAgent Help", action: #selector(showHelp), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newTab() {
        newTerminalTab()
    }

    @objc private func newTerminalTab() {
        tabs.createTerminalTab(workingDirectory: directoryScanner.currentDirectory)
        updateWindowTitle()
    }

    @objc private func newMarkdownTab() {
        tabs.createMarkdownTab(fileURL: nil)
        updateWindowTitle()
    }

    @objc private func gotoTab1() {
        tabs.selectTab(at: 0)
        updateWindowTitle()
    }

    @objc private func gotoTab2() {
        tabs.selectTab(at: 1)
        updateWindowTitle()
    }

    @objc private func gotoTab3() {
        tabs.selectTab(at: 2)
        updateWindowTitle()
    }

    @objc private func gotoTab4() {
        tabs.selectTab(at: 3)
        updateWindowTitle()
    }

    @objc private func gotoTab5() {
        tabs.selectTab(at: 4)
        updateWindowTitle()
    }

    @objc private func gotoTab6() {
        tabs.selectTab(at: 5)
        updateWindowTitle()
    }

    @objc private func gotoTab7() {
        tabs.selectTab(at: 6)
        updateWindowTitle()
    }

    @objc private func gotoTab8() {
        tabs.selectTab(at: 7)
        updateWindowTitle()
    }

    @objc private func gotoTab9() {
        tabs.selectTab(at: 8)
        updateWindowTitle()
    }

    @objc private func gotoTab10() {
        tabs.selectTab(at: 9)
        updateWindowTitle()
    }

    @objc private func closeTab() {
        Task { [weak self] in
            guard let self else { return }
            _ = await tabs.closeActiveTab()
            updateWindowTitle()
        }
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "파일 열기"
        panel.prompt = "열기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openMarkdownFile(url)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openMarkdownFile(_ url: URL) {
        tabs.createMarkdownTab(fileURL: url)
        recentStore.record(url: url)
        directoryScanner.setDirectory(url.deletingLastPathComponent())
        updateWindowTitle()
    }

    @objc private func saveDocument() {
        _ = saveActiveMarkdownDocument()
    }

    @discardableResult
    private func saveActiveMarkdownDocument() -> Bool {
        guard let markdownTab = tabs.activeMarkdownTab else { return false }
        do {
            if markdownTab.state.fileURL == nil {
                guard let url = chooseSaveURL(suggestedName: markdownTab.title) else { return false }
                try markdownTab.state.save(to: url)
                recentStore.record(url: url)
                directoryScanner.setDirectory(url.deletingLastPathComponent())
            } else {
                try markdownTab.state.save()
            }
            updateWindowTitle()
            return true
        } catch {
            showSaveError(error)
            return false
        }
    }

    private func chooseSaveURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "마크다운 문서 저장"
        panel.prompt = "저장"
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = directoryScanner.currentDirectory
        panel.allowedContentTypes = markdownContentTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        return panel.runModal() == .OK ? panel.url : nil
    }

    private var markdownContentTypes: [UTType] {
        [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "txt"),
            .plainText
        ].compactMap { $0 }
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "저장 실패"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func toggleViewMode() {
        guard let markdownTab = tabs.activeMarkdownTab else { return }
        markdownTab.state.document.viewMode = .preview
        updateViewMenuState()
    }

    @objc private func showRawView() {
        guard let markdownTab = tabs.activeMarkdownTab else { return }
        markdownTab.state.document.viewMode = .rawEdit
        updateViewMenuState()
    }

    @objc private func toggleDiff() {
        guard let document = tabs.activeMarkdownTab?.state.document,
              document.diffResult != nil else { return }
        document.showDiff.toggle()
        updateViewMenuState()
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        window?.level = isAlwaysOnTop ? .floating : .normal
        updateWindowTitle()
        updateViewMenuState()
    }

    @objc private func toggleFullScreen() {
        saveWindowFrame(window)
        window?.toggleFullScreen(nil)
    }

    @objc private func showHelp() {
        guard let url = URL(string: "https://github.com/user/markAgent") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateWindowTitle() {
        var title = tabs.activeTab?.title ?? "MarkAgent"
        if tabs.activeTab?.isDirty == true { title += " *" }
        if isAlwaysOnTop { title += " 📌" }
        window?.title = title
        window?.isDocumentEdited = tabs.tabs.contains { $0.isDirty }
        updateViewMenuState()
    }

    private func updateViewMenuState() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        let document = tabs.activeMarkdownTab?.state.document
        viewMenu.items.first { $0.action == #selector(toggleViewMode) }?.state = document?.viewMode == .preview ? .on : .off
        viewMenu.items.first { $0.action == #selector(showRawView) }?.state = document?.viewMode == .rawEdit ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleDiff) }?.isEnabled = document?.diffResult != nil
        viewMenu.items.first { $0.action == #selector(toggleDiff) }?.state = document?.showDiff == true ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleAlwaysOnTop) }?.state = isAlwaysOnTop ? .on : .off
        updateFullScreenMenuItem(viewMenu.items.first { $0.action == #selector(toggleFullScreen) })
    }

    private func updateFullScreenMenuItem(_ menuItem: NSMenuItem?) {
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        menuItem?.title = isFullScreen ? "Exit Full Screen" : "Enter Full Screen"
        menuItem?.state = isFullScreen ? .on : .off
    }

    private func confirmCloseAllDirtyMarkdownTabs() async -> Bool {
        for tab in tabs.tabs {
            guard let markdownTab = tab as? MarkdownTab else { continue }
            guard await markdownTab.state.prepareForClose(prompt: dirtyPrompter) else { return false }
        }
        return true
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
        window?.level = .normal
        updateViewMenuState()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.level = isAlwaysOnTop ? .floating : .normal
        saveWindowFrame(notification.object as? NSWindow)
        updateViewMenuState()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingAfterDirtyConfirmation { return true }
        guard tabs.tabs.contains(where: { $0 is MarkdownTab && $0.isDirty }) else { return true }

        Task { [weak self, weak sender] in
            guard let self, let sender else { return }
            if await confirmCloseAllDirtyMarkdownTabs() {
                isClosingAfterDirtyConfirmation = true
                sender.performClose(nil)
            }
        }
        return false
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newTab),
             #selector(newTerminalTab),
             #selector(newMarkdownTab),
             #selector(openFile),
             #selector(toggleAlwaysOnTop),
             #selector(showHelp):
            return true
        case #selector(toggleFullScreen):
            updateFullScreenMenuItem(menuItem)
            return window != nil
        case #selector(gotoTab1):
            return tabs.tabs.count >= 1
        case #selector(gotoTab2):
            return tabs.tabs.count >= 2
        case #selector(gotoTab3):
            return tabs.tabs.count >= 3
        case #selector(gotoTab4):
            return tabs.tabs.count >= 4
        case #selector(gotoTab5):
            return tabs.tabs.count >= 5
        case #selector(gotoTab6):
            return tabs.tabs.count >= 6
        case #selector(gotoTab7):
            return tabs.tabs.count >= 7
        case #selector(gotoTab8):
            return tabs.tabs.count >= 8
        case #selector(gotoTab9):
            return tabs.tabs.count >= 9
        case #selector(gotoTab10):
            return tabs.tabs.count >= 10
        case #selector(closeTab):
            return tabs.activeTab != nil
        case #selector(saveDocument):
            return tabs.activeMarkdownTab != nil
        case #selector(toggleViewMode):
            menuItem.state = tabs.activeMarkdownTab?.state.document.viewMode == .preview ? .on : .off
            return tabs.activeMarkdownTab != nil
        case #selector(showRawView):
            menuItem.state = tabs.activeMarkdownTab?.state.document.viewMode == .rawEdit ? .on : .off
            return tabs.activeMarkdownTab != nil
        case #selector(toggleDiff):
            let document = tabs.activeMarkdownTab?.state.document
            menuItem.state = document?.showDiff == true ? .on : .off
            return document?.diffResult != nil
        default:
            return true
        }
    }
}
