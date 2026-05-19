import Foundation

@MainActor
@Observable
final class DirectoryScanner {
    var currentDirectory: URL
    private(set) var entries: [FileEntry] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    init(currentDirectory: URL) {
        self.currentDirectory = currentDirectory
        reload()
    }

    func reload() {
        isLoading = true
        errorMessage = nil
        do {
            entries = try Self.scan(directory: currentDirectory)
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
        isLoading = false
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

    private static func scan(directory: URL) throws -> [FileEntry] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents.map { url in
            let name = url.lastPathComponent
            let kind: FileEntry.Kind
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                kind = .directory
            } else if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
                kind = .markdown
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
