import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    let document = MarkdownDocument()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadFromCLIArguments()

        let contentView = ContentView(document: document)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = document.fileURL?.lastPathComponent ?? "MarkAgent"
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
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
        case .failure(let error):
            document.errorMessage = error.errorDescription
        }
    }
}
