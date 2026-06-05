import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let tabs = TabCollection()
    let recentStore = RecentDocumentStore()
    let snippetStore = PromptSnippetStore()
    let sidebarSearchCommands = SidebarSearchCommandCenter()
    let directoryScanner: DirectoryScanner
    let gitRepositoryStatus: GitRepositoryStatus
    let dirtyPrompter: AppDirtyDocumentPrompter
    var isAlwaysOnTop = false
    var window: NSWindow?

    private var isClosingAfterDirtyConfirmation = false
    private let windowFrameDefaultsKey = "MarkAgent.windowFrame"
    private let leftSidebarVisibleDefaultsKey = "isLeftSidebarVisible"
    private var rootHostingView: NSHostingView<AnyView>?
    private var searchKeyMonitor: Any?

    override init() {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        self.directoryScanner = DirectoryScanner(currentDirectory: homeURL)
        self.gitRepositoryStatus = GitRepositoryStatus(currentDirectory: homeURL)
        self.dirtyPrompter = AppDirtyDocumentPrompter(window: nil)
        super.init()
        tabs.dirtyPrompter = dirtyPrompter
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        setupMenu()
        setupWindow()
        removeSystemTabBarMenuItems()
        tabs.createTerminalTab(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        openLaunchTargetIfNeeded()
        updateWindowTitle()
        setupSearchKeyMonitor()
        NSRunningApplication.current.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
        }
    }

    private func setupWindow() {
        let hostingView = NSHostingView(rootView: makeRootView())

        let window = MarkAgentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.titleVisibility = .hidden
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.level = .normal
        window.delegate = self
        window.tabGroupKeybindHandler = { [weak self] event in
            self?.handleTabGroupKeybind(event) ?? false
        }
        window.terminalKeybindHandler = { [weak self] event in
            self?.handleTerminalTextKeybind(event) ?? false
        }
        self.window = window
        self.rootHostingView = hostingView
        dirtyPrompter.window = window
        setupTitlebarStatus(for: window)
        gitRepositoryStatus.refresh(for: directoryScanner.currentDirectory)

        restoreWindowFrame(window)
        window.makeKeyAndOrderFront(nil)
        updateWindowTitle()
    }

    private func makeRootView() -> AnyView {
        let appTheme = GhosttyConfig.userConfig()?.colorTheme
        let contentView = MainContainerView(
            tabs: tabs,
            scanner: directoryScanner,
            recentStore: recentStore,
            snippetStore: snippetStore,
            searchCommandCenter: sidebarSearchCommands,
            onOpenFile: { [weak self] in
                self?.openFile()
            },
            onDocumentChanged: { [weak self] in
                self?.updateWindowTitle()
            },
            onConfigurationSaved: { [weak self] in
                self?.reloadConfiguration()
            },
            onDirectoryChanged: { [weak self] directory in
                self?.gitRepositoryStatus.refresh(for: directory)
            }
        )
        .environment(\.terminalAppTheme, appTheme)
        .preferredColorScheme(appTheme?.preferredColorScheme)
        return AnyView(contentView)
    }

    private func setupTitlebarStatus(for window: NSWindow) {
        let pathView = TitlebarPathView(scanner: directoryScanner)
            .frame(minWidth: 360, idealWidth: 560, maxWidth: 720, alignment: .leading)
        let pathController = NSTitlebarAccessoryViewController()
        pathController.view = titlebarHostingView(rootView: pathView, width: 560)
        pathController.layoutAttribute = .left
        window.addTitlebarAccessoryViewController(pathController)

        let branchView = TitlebarGitBranchView(status: gitRepositoryStatus)
            .frame(minWidth: 80, idealWidth: 420, maxWidth: 640, alignment: .trailing)
        let branchController = NSTitlebarAccessoryViewController()
        branchController.view = titlebarHostingView(rootView: branchView, width: 420)
        branchController.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(branchController)
    }

    private func titlebarHostingView<Content: View>(rootView: Content, width: CGFloat) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 28)
        hostingView.autoresizingMask = [.width, .height]
        return hostingView
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

        let aboutItem = NSMenuItem(title: String(localized: "About MarkAgent"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(showPreferences), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let reloadConfigurationItem = NSMenuItem(title: String(localized: "Reload Configuration"), action: #selector(reloadConfiguration), keyEquivalent: ",")
        reloadConfigurationItem.keyEquivalentModifierMask = [.command, .shift]
        reloadConfigurationItem.target = self
        appMenu.addItem(reloadConfigurationItem)

        let openGhosttyConfigItem = NSMenuItem(title: String(localized: "Open Ghostty config"), action: #selector(openGhosttyConfig), keyEquivalent: "")
        openGhosttyConfigItem.target = self
        appMenu.addItem(openGhosttyConfigItem)

        appMenu.addItem(.separator())

        let servicesMenuItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: String(localized: "Services"))
        servicesMenuItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesMenuItem)

        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: String(localized: "Hide MarkAgent"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: String(localized: "Quit MarkAgent"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenuItem.submenu = fileMenu

        let newTerminalItem = NSMenuItem(title: String(localized: "New Terminal Tab"), action: #selector(newTab), keyEquivalent: "t")
        newTerminalItem.target = self
        fileMenu.addItem(newTerminalItem)

        let newMarkdownItem = NSMenuItem(title: String(localized: "New Markdown Tab"), action: #selector(newMarkdownTab), keyEquivalent: "n")
        newMarkdownItem.target = self
        fileMenu.addItem(newMarkdownItem)

        fileMenu.addItem(.separator())

        let openItem = NSMenuItem(title: String(localized: "Open…"), action: #selector(openFile), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        fileMenu.addItem(.separator())

        let saveItem = NSMenuItem(title: String(localized: "Save"), action: #selector(saveDocument), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(saveItem)

        fileMenu.addItem(.separator())

        let closeTabItem = NSMenuItem(title: String(localized: "Close Tab"), action: #selector(closeTab), keyEquivalent: "w")
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Delete"), action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())

        let focusFileSearchItem = NSMenuItem(title: String(localized: "File Search"), action: #selector(focusFileSearch), keyEquivalent: "f")
        focusFileSearchItem.keyEquivalentModifierMask = [.command, .shift]
        focusFileSearchItem.target = self
        editMenu.addItem(focusFileSearchItem)

        let focusContentSearchItem = NSMenuItem(title: String(localized: "Content Search"), action: #selector(focusContentSearch), keyEquivalent: "g")
        focusContentSearchItem.keyEquivalentModifierMask = [.command, .shift]
        focusContentSearchItem.target = self
        editMenu.addItem(focusContentSearchItem)

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: String(localized: "View"))
        viewMenuItem.submenu = viewMenu

        let gotoTabItems: [(title: String, selector: Selector, key: String)] = [
            (String(format: String(localized: "Select Tab %@"), "1"), #selector(gotoTab1), "1"),
            (String(format: String(localized: "Select Tab %@"), "2"), #selector(gotoTab2), "2"),
            (String(format: String(localized: "Select Tab %@"), "3"), #selector(gotoTab3), "3"),
            (String(format: String(localized: "Select Tab %@"), "4"), #selector(gotoTab4), "4"),
            (String(format: String(localized: "Select Tab %@"), "5"), #selector(gotoTab5), "5"),
            (String(format: String(localized: "Select Tab %@"), "6"), #selector(gotoTab6), "6"),
            (String(format: String(localized: "Select Tab %@"), "7"), #selector(gotoTab7), "7"),
            (String(format: String(localized: "Select Tab %@"), "8"), #selector(gotoTab8), "8"),
            (String(format: String(localized: "Select Tab %@"), "9"), #selector(gotoTab9), "9"),
            (String(format: String(localized: "Select Tab %@"), "10"), #selector(gotoTab10), "0"),
        ]
        for item in gotoTabItems {
            let menuItem = NSMenuItem(title: item.title, action: item.selector, keyEquivalent: item.key)
            menuItem.target = self
            viewMenu.addItem(menuItem)
        }

        viewMenu.addItem(.separator())

        let toggleModeItem = NSMenuItem(title: String(localized: "Preview"), action: #selector(toggleViewMode), keyEquivalent: "p")
        toggleModeItem.keyEquivalentModifierMask = [.command, .control]
        toggleModeItem.target = self
        viewMenu.addItem(toggleModeItem)

        let rawViewItem = NSMenuItem(title: String(localized: "Raw Edit"), action: #selector(showRawView), keyEquivalent: "r")
        rawViewItem.keyEquivalentModifierMask = [.command, .control]
        rawViewItem.target = self
        viewMenu.addItem(rawViewItem)

        viewMenu.addItem(.separator())

        let toggleLeftSidebarItem = NSMenuItem(title: String(localized: "Toggle Left Sidebar"), action: #selector(toggleLeftSidebar), keyEquivalent: "s")
        toggleLeftSidebarItem.keyEquivalentModifierMask = [.command, .option]
        toggleLeftSidebarItem.target = self
        viewMenu.addItem(toggleLeftSidebarItem)

        let toggleDiffItem = NSMenuItem(title: String(localized: "Toggle Diff"), action: #selector(toggleDiff), keyEquivalent: "d")
        toggleDiffItem.target = self
        viewMenu.addItem(toggleDiffItem)

        viewMenu.addItem(.separator())

        let alwaysOnTopItem = NSMenuItem(title: String(localized: "Always on Top"), action: #selector(toggleAlwaysOnTop), keyEquivalent: "t")
        alwaysOnTopItem.keyEquivalentModifierMask = [.command, .shift]
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = .off
        viewMenu.addItem(alwaysOnTopItem)

        viewMenu.addItem(.separator())
        let enterFullScreenItem = NSMenuItem(title: String(localized: "Enter Full Screen"), action: #selector(toggleFullScreen), keyEquivalent: "f")
        enterFullScreenItem.keyEquivalentModifierMask = [.command, .control]
        enterFullScreenItem.target = self
        viewMenu.addItem(enterFullScreenItem)
        removeSystemTabBarMenuItems(from: viewMenu)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: String(localized: "Help"))
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu
        let helpItem = NSMenuItem(title: String(localized: "MarkAgent Help"), action: #selector(showHelp), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
        removeSystemTabBarMenuItems()
    }

    private func setupSearchKeyMonitor() {
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let mode = self.sidebarSearchMode(for: event) else { return event }
            self.focusSidebarSearch(mode: mode)
            return nil
        }
    }

    private func sidebarSearchMode(for event: NSEvent) -> SidebarSearchMode? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return nil }

        switch key {
        case "f":
            return .files
        case "g":
            return .grep
        default:
            return nil
        }
    }

    private func removeSystemTabBarMenuItems(from menu: NSMenu? = NSApp.mainMenu?.item(withTitle: String(localized: "View"))?.submenu) {
        guard let menu else { return }

        let toggleTabBarSelector = NSSelectorFromString("toggleTabBar:")
        for item in menu.items where item.action == toggleTabBarSelector || item.title == "Show Tab Bar" {
            menu.removeItem(item)
        }
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

    @objc private func reloadConfiguration() {
        for tab in tabs.tabs {
            guard let terminalTab = tab as? TerminalTab else { continue }
            terminalTab.state.reloadConfiguration()
        }

        rootHostingView?.rootView = makeRootView()
        updateWindowTitle()
    }

    @objc private func openGhosttyConfig() {
        openMarkdownFile(ghosttyConfigURL())
    }

    private func ghosttyConfigURL() -> URL {
        if let userConfig = GhosttyConfig.userConfig() {
            return userConfig.url
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty/config")
    }

    private func shouldReloadConfiguration(for url: URL?) -> Bool {
        guard let url else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL == ghosttyConfigURL().resolvingSymlinksInPath().standardizedFileURL
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
            if tabs.activeTerminalTab != nil {
                guard await confirmCloseActiveTerminalTab() else { return }
            }
            _ = await tabs.closeActiveTab()
            updateWindowTitle()
        }
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "파일 열기")
        panel.prompt = String(localized: "열기")
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

    private func openLaunchTargetIfNeeded() {
        guard let fileURL = launchTargetFileURL() else { return }
        openMarkdownFile(fileURL)
    }

    private func launchTargetFileURL() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments.dropFirst()

        for argument in arguments {
            guard !argument.hasPrefix("-psn_") else { continue }
            guard !argument.hasPrefix("-") else { continue }

            switch MarkdownDocument.resolveFileURL(from: argument) {
            case .success(let url):
                return url
            case .failure:
                continue
            }
        }

        return nil
    }

    @objc private func saveDocument() {
        _ = saveActiveMarkdownDocument()
    }

    @discardableResult
    private func saveActiveMarkdownDocument() -> Bool {
        guard let markdownTab = tabs.activeMarkdownTab else { return false }

        let document = markdownTab.state.document
        let wasDirty = document.isDirty
        let currentFileURL = markdownTab.state.fileURL

        do {
            let savedURL: URL
            if currentFileURL == nil {
                guard let url = chooseSaveURL(suggestedName: markdownTab.title) else { return false }
                try markdownTab.state.save(to: url)
                recentStore.record(url: url)
                directoryScanner.setDirectory(url.deletingLastPathComponent())
                savedURL = url
            } else {
                try markdownTab.state.save()
                guard let resolvedURL = markdownTab.state.fileURL ?? currentFileURL else {
                    return false
                }
                savedURL = resolvedURL
            }

            if wasDirty, shouldReloadConfiguration(for: savedURL) {
                reloadConfiguration()
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
        panel.title = String(localized: "마크다운 문서 저장")
        panel.prompt = String(localized: "저장")
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
        alert.messageText = String(localized: "저장 실패")
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

    @objc private func toggleLeftSidebar() {
        UserDefaults.standard.set(!isLeftSidebarVisible, forKey: leftSidebarVisibleDefaultsKey)
        updateViewMenuState()
    }

    @objc private func focusFileSearch() {
        focusSidebarSearch(mode: .files)
    }

    @objc private func focusContentSearch() {
        focusSidebarSearch(mode: .grep)
    }

    private func focusSidebarSearch(mode: SidebarSearchMode) {
        UserDefaults.standard.set(true, forKey: leftSidebarVisibleDefaultsKey)
        sidebarSearchCommands.focus(mode)
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate()
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

    @objc private func showAbout() {
        tabs.showAboutTab()
        updateWindowTitle()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate()
    }

    @objc private func showPreferences() {
        tabs.showSettingsTab()
        updateWindowTitle()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate()
    }

    @objc private func showHelp() {
        guard let url = Bundle.main.url(forResource: "README", withExtension: "md") else {
            tabs.showAboutTab()
            updateWindowTitle()
            window?.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate()
            return
        }

        openFileInMarkdownTab(url)
    }

    private func openFileInMarkdownTab(_ url: URL) {
        tabs.createMarkdownTab(fileURL: url)
        recentStore.record(url: url)
        directoryScanner.setDirectory(url.deletingLastPathComponent())
        updateWindowTitle()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate()
    }

    private func updateWindowTitle() {
        var title = tabs.activeTab?.title ?? "MarkAgent"
        if tabs.activeTab?.isDirty == true { title += " *" }
        if isAlwaysOnTop { title += " 📌" }
        window?.title = title
        window?.isDocumentEdited = tabs.tabs.contains { $0.isDirty }
        updateViewMenuState()
    }

    private func handleTabGroupKeybind(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command,
              let key = event.charactersIgnoringModifiers,
              let shortcutNumber = Int(key),
              tabs.selectGroup(shortcutNumber: shortcutNumber) else {
            return false
        }

        updateWindowTitle()
        return true
    }

    private func handleTerminalTextKeybind(_ event: NSEvent) -> Bool {
        guard tabs.activeTerminalTab != nil else { return false }
        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }

        var modifiers: EventModifierMask = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }

        guard modifiers.contains(EventModifierMask.command) else { return false }
        if modifiers == [.command, .shift], ["f", "g"].contains(key.lowercased()) {
            return false
        }
        if key.lowercased() == "w", modifiers == [.command] {
            return false
        }
        return tabs.activeTerminalTab?.state.sendConfiguredKeybind(event, key: key, modifiers: modifiers) == true
    }

    private func updateViewMenuState() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: String(localized: "View"))?.submenu else { return }
        let document = tabs.activeMarkdownTab?.state.document
        viewMenu.items.first { $0.action == #selector(toggleViewMode) }?.state = document?.viewMode == .preview ? .on : .off
        viewMenu.items.first { $0.action == #selector(showRawView) }?.state = document?.viewMode == .rawEdit ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleDiff) }?.isEnabled = document?.diffResult != nil
        viewMenu.items.first { $0.action == #selector(toggleDiff) }?.state = document?.showDiff == true ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleLeftSidebar) }?.state = isLeftSidebarVisible ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleAlwaysOnTop) }?.state = isAlwaysOnTop ? .on : .off
        updateFullScreenMenuItem(viewMenu.items.first { $0.action == #selector(toggleFullScreen) })
    }

    private var isLeftSidebarVisible: Bool {
        guard UserDefaults.standard.object(forKey: leftSidebarVisibleDefaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: leftSidebarVisibleDefaultsKey)
    }

    private func updateFullScreenMenuItem(_ menuItem: NSMenuItem?) {
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        menuItem?.title = isFullScreen ? String(localized: "Exit Full Screen") : String(localized: "Enter Full Screen")
        menuItem?.state = isFullScreen ? .on : .off
    }

    private func confirmCloseAllDirtyMarkdownTabs() async -> Bool {
        for tab in tabs.tabs {
            guard let markdownTab = tab as? MarkdownTab else { continue }
            guard await markdownTab.state.prepareForClose(prompt: dirtyPrompter) else { return false }
        }
        return true
    }

    private func confirmCloseActiveTerminalTab() async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Close terminal tab?")
        alert.informativeText = String(localized: "Closing this terminal tab will end its session. Do you want to close it?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Close Tab"))
        alert.addButton(withTitle: String(localized: "취소"))

        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
        } else {
            response = alert.runModal()
        }

        return response == .alertFirstButtonReturn
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
             #selector(toggleLeftSidebar),
             #selector(focusFileSearch),
             #selector(focusContentSearch),
             #selector(toggleAlwaysOnTop),
             #selector(showAbout),
             #selector(showPreferences),
             #selector(showHelp),
             #selector(openGhosttyConfig):
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
        case #selector(toggleLeftSidebar):
            menuItem.state = isLeftSidebarVisible ? .on : .off
            return true
        default:
            return true
        }
    }
}
