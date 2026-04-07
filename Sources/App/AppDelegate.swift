import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    let document = MarkdownDocument()
    private var fileWatcher: FileWatcher?
    private var isAlwaysOnTop = true
    private let cliArguments: CLIArguments

    init(cliArguments: CLIArguments) {
        self.cliArguments = cliArguments
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadFromCLIArguments()
        setupWindow()
        setupMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        cliArguments.waitMode
    }

    private func setupWindow() {
        let contentView = ContentView(document: document)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
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

        NSApp.activate(ignoringOtherApps: true)
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

        // App 메뉴
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(
            title: "Quit MarkAgent",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // File 메뉴
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let saveItem = NSMenuItem(
            title: "Save",
            action: #selector(saveDocument),
            keyEquivalent: "s"
        )
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.target = self
        fileMenu.addItem(saveItem)

        fileMenu.addItem(.separator())

        let templateItem = NSMenuItem(
            title: "Insert Template...",
            action: #selector(showTemplatePicker),
            keyEquivalent: "t"
        )
        templateItem.keyEquivalentModifierMask = [.command]
        templateItem.target = self
        fileMenu.addItem(templateItem)

        // View 메뉴
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let toggleModeItem = NSMenuItem(
            title: "Toggle Preview/Edit",
            action: #selector(toggleViewMode),
            keyEquivalent: "e"
        )
        toggleModeItem.keyEquivalentModifierMask = [.command]
        toggleModeItem.target = self
        viewMenu.addItem(toggleModeItem)

        let toggleDiffItem = NSMenuItem(
            title: "Toggle Diff",
            action: #selector(toggleDiff),
            keyEquivalent: "d"
        )
        toggleDiffItem.keyEquivalentModifierMask = [.command]
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

        // Window 메뉴
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func saveDocument() {
        do {
            try document.save()
            updateWindowTitle()
        } catch {
            let alert = NSAlert()
            alert.messageText = "저장 실패"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func toggleViewMode() {
        document.viewMode = document.viewMode == .preview ? .edit : .preview
    }

    @objc private func toggleDiff() {
        guard document.diffResult != nil else { return }
        document.showDiff.toggle()
    }

    @objc private func showTemplatePicker() {
        guard let window else { return }
        let picker = NSHostingController(
            rootView: TemplatePicker(
                onApply: { [weak self] renderedContent in
                    self?.document.editableContent = renderedContent
                    self?.document.isLoaded = true
                    self?.document.viewMode = .edit
                    window.sheets.first?.close()
                },
                onDismiss: {
                    window.sheets.first?.close()
                }
            )
        )
        picker.view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let sheetWindow = NSWindow(contentViewController: picker)
        window.beginSheet(sheetWindow)
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        window?.level = isAlwaysOnTop ? .floating : .normal
        updateWindowTitle()
        updateToggleMenuItemState()
    }

    private func updateWindowTitle() {
        let fileName = document.fileURL?.lastPathComponent ?? "MarkAgent"
        var title = fileName
        if isAlwaysOnTop { title += " 📌" }
        if cliArguments.waitMode { title += " [wait]" }
        window?.title = title
        window?.isDocumentEdited = document.isDirty
    }

    private func updateToggleMenuItemState() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        viewMenu.items.first { $0.action == #selector(toggleAlwaysOnTop) }?.state = isAlwaysOnTop ? .on : .off
    }

    private func loadFromCLIArguments() {
        guard let path = cliArguments.filePath else {
            document.errorMessage = DocumentError.noFileSpecified.errorDescription
            return
        }

        switch MarkdownDocument.resolveFileURL(from: path) {
        case .success(let url):
            document.load(from: url)
            startWatching(url: url)
        case .failure(let error):
            document.errorMessage = error.errorDescription
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
        guard document.isDirty, document.fileURL != nil else { return true }

        let alert = NSAlert()
        alert.messageText = "저장되지 않은 변경사항이 있습니다."
        alert.informativeText = "변경사항을 저장하시겠습니까?"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            try? document.save()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
