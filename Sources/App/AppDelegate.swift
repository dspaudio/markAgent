import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    let document = MarkdownDocument()
    private var fileWatcher: FileWatcher?
    private var isAlwaysOnTop = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadFromCLIArguments()
        setupWindow()
        setupMenu()
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

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit MarkAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        let toggleItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTop),
            keyEquivalent: "t"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        toggleItem.state = .on
        windowMenu.addItem(toggleItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        window?.level = isAlwaysOnTop ? .floating : .normal
        updateWindowTitle()
        updateToggleMenuItemState()
    }

    private func updateWindowTitle() {
        let fileName = document.fileURL?.lastPathComponent ?? "MarkAgent"
        window?.title = isAlwaysOnTop ? "\(fileName) 📌" : fileName
    }

    private func updateToggleMenuItemState() {
        guard let windowMenu = NSApp.mainMenu?.item(withTitle: "Window")?.submenu else { return }
        windowMenu.items.first { $0.action == #selector(toggleAlwaysOnTop) }?.state = isAlwaysOnTop ? .on : .off
    }

    private func loadFromCLIArguments() {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            document.errorMessage = DocumentError.noFileSpecified.errorDescription
            return
        }

        let path = args[1]
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
            doc.load(from: url)
        }
        fileWatcher = watcher
        Task {
            await watcher.startWatching(url: url)
        }
    }
}
