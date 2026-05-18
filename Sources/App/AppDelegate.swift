import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    let document = MarkdownDocument()
    private let recentStore = RecentDocumentStore()
    private var fileWatcher: FileWatcher?
    private var isAlwaysOnTop = true
    private let cliArguments: CLIArguments

    init(cliArguments: CLIArguments) {
        self.cliArguments = cliArguments
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        loadFromCLIArguments()
        setupWindow()
        NSRunningApplication.current.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func setupWindow() {
        let contentView = ContentView(
            document: document,
            recentStore: recentStore,
            onNewDocument: { [weak self] in
                self?.newDocument()
            },
            onOpenFile: { [weak self] in
                self?.openFile()
            },
            onOpenRecent: { [weak self] url in
                self?.openDocumentIfAllowed(url: url)
            },
            onDocumentChanged: { [weak self] in
                self?.updateWindowTitle()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        positionWindowOnRight(window)
        updateWindowTitle()
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

        // MARK: App 메뉴
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
        appMenu.addItem(NSMenuItem(
            title: "Hide MarkAgent",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit MarkAgent",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // MARK: File 메뉴
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let newItem = NSMenuItem(
            title: "New",
            action: #selector(newDocument),
            keyEquivalent: "n"
        )
        newItem.target = self
        fileMenu.addItem(newItem)

        fileMenu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "Open…",
            action: #selector(openFile),
            keyEquivalent: "o"
        )
        openItem.target = self
        fileMenu.addItem(openItem)

        fileMenu.addItem(.separator())

        let saveItem = NSMenuItem(
            title: "Save",
            action: #selector(saveDocument),
            keyEquivalent: "s"
        )
        saveItem.target = self
        fileMenu.addItem(saveItem)

        fileMenu.addItem(.separator())

        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileMenu.addItem(closeItem)

        // MARK: Edit 메뉴
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

        // MARK: View 메뉴
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let toggleModeItem = NSMenuItem(
            title: "Preview",
            action: #selector(toggleViewMode),
            keyEquivalent: "1"
        )
        toggleModeItem.target = self
        viewMenu.addItem(toggleModeItem)

        let rawViewItem = NSMenuItem(
            title: "Raw Edit",
            action: #selector(showRawView),
            keyEquivalent: "2"
        )
        rawViewItem.target = self
        viewMenu.addItem(rawViewItem)

        let toggleDiffItem = NSMenuItem(
            title: "Toggle Diff",
            action: #selector(toggleDiff),
            keyEquivalent: "d"
        )
        toggleDiffItem.target = self
        viewMenu.addItem(toggleDiffItem)

        viewMenu.addItem(.separator())

        let alwaysOnTopItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTop),
            keyEquivalent: "t"
        )
        alwaysOnTopItem.keyEquivalentModifierMask = [.command, .shift]
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = .on
        viewMenu.addItem(alwaysOnTopItem)

        viewMenu.addItem(.separator())

        let enterFullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        enterFullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(enterFullScreenItem)

        // MARK: Window 메뉴
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))

        // MARK: Help 메뉴
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        let helpItem = NSMenuItem(
            title: "MarkAgent Help",
            action: #selector(showHelp),
            keyEquivalent: "?"
        )
        helpItem.target = self
        helpMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func saveDocument() {
        _ = saveDocumentInteractively()
    }

    @discardableResult
    private func saveDocumentInteractively() -> Bool {
        do {
            if document.fileURL == nil {
                guard let url = chooseSaveURL() else { return false }
                try saveDocumentAt(url)
            } else {
                try document.save()
            }
            updateWindowTitle()
            return true
        } catch {
            showSaveError(error)
            return false
        }
    }

    private func saveDocumentAt(_ url: URL) throws {
        Task {
            await fileWatcher?.stopWatching()
        }
        try document.save(to: url)
        recentStore.record(url: url)
        startWatching(url: url)
    }

    private func chooseSaveURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "마크다운 문서 저장"
        panel.prompt = "저장"
        panel.nameFieldStringValue = suggestedSaveFileName
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText
        ].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        return panel.runModal() == .OK ? panel.url : nil
    }

    private var suggestedSaveFileName: String {
        document.fileURL?.lastPathComponent ?? "Untitled.md"
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "저장 실패"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func newDocument() {
        guard canReplaceCurrentDocument() else { return }

        Task {
            await fileWatcher?.stopWatching()
        }
        fileWatcher = nil
        document.resetToNewDocument()
        updateWindowTitle()
    }

    @objc private func openFile() {
        guard canReplaceCurrentDocument() else { return }

        let panel = NSOpenPanel()
        panel.title = "마크다운 파일 열기"
        panel.prompt = "열기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "txt"),
            .plainText
        ].compactMap { $0 }

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openDocument(url: url)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc private func toggleViewMode() {
        document.viewMode = .preview
        updateViewMenuState()
    }

    @objc private func showRawView() {
        document.viewMode = .rawEdit
        updateViewMenuState()
    }

    @objc private func toggleDiff() {
        guard document.diffResult != nil else { return }
        document.showDiff.toggle()
        updateViewMenuState()
    }

    @objc private func showHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/user/markAgent")!)
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        window?.level = isAlwaysOnTop ? .floating : .normal
        updateWindowTitle()
        updateViewMenuState()
    }

    private func updateWindowTitle() {
        let fileName = document.fileURL?.lastPathComponent ?? "MarkAgent"
        var title = fileName
        if document.isDirty { title += " *" }
        if isAlwaysOnTop { title += " 📌" }
        if cliArguments.waitMode { title += " [wait]" }
        window?.title = title
        window?.isDocumentEdited = document.isDirty
    }

    private func updateViewMenuState() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        viewMenu.items.first { $0.action == #selector(toggleViewMode) }?.state = document.viewMode == .preview ? .on : .off
        viewMenu.items.first { $0.action == #selector(showRawView) }?.state = document.viewMode == .rawEdit ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleDiff) }?.isEnabled = document.diffResult != nil
        viewMenu.items.first { $0.action == #selector(toggleDiff) }?.state = document.showDiff ? .on : .off
        viewMenu.items.first { $0.action == #selector(toggleAlwaysOnTop) }?.state = isAlwaysOnTop ? .on : .off
    }

    private func loadFromCLIArguments() {
        guard let path = cliArguments.filePath else {
            document.isLoaded = true
            document.errorMessage = nil
            return
        }

        switch MarkdownDocument.resolveFileURL(from: path) {
        case .success(let url):
            openDocument(url: url)
        case .failure(let error):
            document.errorMessage = error.errorDescription
        }
    }

    private func openDocumentIfAllowed(url: URL) {
        guard canReplaceCurrentDocument() else { return }
        openDocument(url: url)
    }

    private func openDocument(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            document.errorMessage = DocumentError.fileNotFound(url.path).errorDescription
            document.isLoaded = false
            updateWindowTitle()
            return
        }

        Task {
            await fileWatcher?.stopWatching()
        }

        document.load(from: url)
        document.viewMode = .rawEdit
        recentStore.record(url: url)
        startWatching(url: url)
        updateWindowTitle()
    }

    private func canReplaceCurrentDocument() -> Bool {
        guard document.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "저장되지 않은 변경사항이 있습니다."
        alert.informativeText = "다른 파일을 열기 전에 현재 변경사항을 저장하시겠습니까?"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveDocumentInteractively()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func startWatching(url: URL) {
        let doc = document
        let watcher = FileWatcher {
            doc.loadIfNotRecentlySaved(from: url)
        }
        fileWatcher = watcher
        Task {
            await watcher.startWatching(url: url)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard document.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "저장되지 않은 변경사항이 있습니다."
        alert.informativeText = "변경사항을 저장하시겠습니까?"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveDocumentInteractively()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newDocument),
             #selector(openFile),
             #selector(saveDocument),
             #selector(showHelp):
            return true
        case #selector(toggleViewMode):
            menuItem.state = document.viewMode == .preview ? .on : .off
            return true
        case #selector(showRawView):
            menuItem.state = document.viewMode == .rawEdit ? .on : .off
            return true
        case #selector(toggleDiff):
            menuItem.state = document.showDiff ? .on : .off
            return document.diffResult != nil
        case #selector(toggleAlwaysOnTop):
            menuItem.state = isAlwaysOnTop ? .on : .off
            return true
        default:
            return true
        }
    }
}
