import Foundation

@MainActor
@Observable
final class DirectoryScanner {
    var currentDirectory: URL
    var includeHiddenFiles: Bool
    private(set) var entries: [FileEntry] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var scanTask: Task<Void, Never>?
    private var scanToken = 0

    init(currentDirectory: URL, includeHiddenFiles: Bool = false) {
        self.currentDirectory = currentDirectory
        self.includeHiddenFiles = includeHiddenFiles
        reload()
    }

    func reload() {
        let directory = currentDirectory
        let includeHiddenFiles = includeHiddenFiles
        scanToken += 1
        let token = scanToken
        scanTask?.cancel()
        isLoading = true
        errorMessage = nil

        scanTask = Task { [directory, includeHiddenFiles, token] in
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try Self.scan(directory: directory, includeHidden: includeHiddenFiles)
                }.value
                guard !Task.isCancelled, token == self.scanToken, self.currentDirectory == directory else { return }
                self.entries = entries
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, token == self.scanToken, self.currentDirectory == directory else { return }
                self.errorMessage = error.localizedDescription
                self.entries = []
                self.isLoading = false
            }
        }
    }

    func enterDirectory(_ url: URL) {
        currentDirectory = url
        reload()
    }

    func goUp() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent.path != currentDirectory.path else { return }
        currentDirectory = parent
        reload()
    }

    func setDirectory(_ url: URL) {
        currentDirectory = url
        reload()
    }

    func setIncludeHiddenFiles(_ includeHiddenFiles: Bool) {
        guard self.includeHiddenFiles != includeHiddenFiles else { return }
        self.includeHiddenFiles = includeHiddenFiles
        reload()
    }

    nonisolated static func scan(directory: URL, includeHidden: Bool = false) throws -> [FileEntry] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        )

        return contents.map { url in
            let name = url.lastPathComponent
            let kind: FileEntry.Kind
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                kind = .directory
            } else if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
                kind = .markdown
            } else if FileEntry.isImageURL(url) {
                kind = .image
            } else {
                kind = .file
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return FileEntry(url: url, name: name, kind: kind, sizeBytes: size, modifiedAt: modified)
        }.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
