import Foundation

@MainActor
@Observable
final class MarkdownTabState {
    let id: UUID
    let document: MarkdownDocument
    private var fileWatcher: FileWatcher?

    var title: String { document.fileURL?.lastPathComponent ?? "Untitled.md" }
    var fileURL: URL? { document.fileURL }
    var isDirty: Bool { document.isDirty }

    init(id: UUID = UUID(), fileURL: URL? = nil) {
        self.id = id
        self.document = MarkdownDocument()
        if let url = fileURL {
            load(from: url)
        } else {
            document.isLoaded = true
        }
    }

    func load(from url: URL) {
        document.load(from: url)
        startWatching(url: url)
    }

    func save() throws {
        try document.save()
        if let url = document.fileURL {
            startWatching(url: url)
        }
    }

    func save(to url: URL) throws {
        try document.save(to: url)
        startWatching(url: url)
    }

    func startWatching(url: URL) {
        Task {
            await stopWatching()
            let watcher = FileWatcher { [weak self] in
                guard let self else { return }
                self.document.loadIfNotRecentlySaved(from: url)
            }
            self.fileWatcher = watcher
            await watcher.startWatching(url: url)
        }
    }

    func stopWatching() async {
        await fileWatcher?.stopWatching()
        fileWatcher = nil
    }

    func prepareForClose(prompt: DirtyDocumentPrompting?) async -> Bool {
        if isDirty {
            guard let prompt = prompt else { return false }
            let confirmed = await prompt.confirmCloseDirtyDocument(title: title, fileURL: fileURL) { url in
                if let url {
                    try self.save(to: url)
                } else {
                    try self.save()
                }
            }
            if confirmed {
                await stopWatching()
                return true
            } else {
                return false
            }
        } else {
            await stopWatching()
            return true
        }
    }
}
