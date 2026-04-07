import Foundation

enum ViewMode {
    case preview
    case edit
}

@Observable
@MainActor
final class MarkdownDocument {
    var content: String = ""
    var editableContent: String = ""
    var fileURL: URL?
    var errorMessage: String?
    var isLoaded: Bool = false
    var isExternalUpdatePending: Bool = false
    var viewMode: ViewMode = .preview

    var previousContent: String?
    var diffResult: DiffResult?
    var showDiff: Bool = false

    private var pendingExternalContent: String?
    private var lastSaveTime: Date?

    var isDirty: Bool {
        editableContent != content
    }

    func load(from url: URL) {
        do {
            let newContent = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            errorMessage = nil
            isLoaded = true

            if isDirty {
                pendingExternalContent = newContent
                isExternalUpdatePending = true
            } else {
                let oldContent = content
                content = newContent
                editableContent = newContent
                computeDiffInBackground(old: oldContent, new: newContent)
            }
        } catch {
            isLoaded = false
            errorMessage = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
    }

    func clearDiff() {
        diffResult = nil
        showDiff = false
        previousContent = nil
    }

    private func computeDiffInBackground(old: String, new: String) {
        previousContent = old
        Task.detached(priority: .utility) {
            let result = DiffEngine.compute(old: old, new: new)
            await MainActor.run {
                self.diffResult = result.isEmpty ? nil : result
                if self.diffResult != nil {
                    self.showDiff = true
                }
            }
        }
    }

    // FileWatcher 콜백에서 호출 — 앱 자체 저장 직후 이벤트는 무시
    func loadIfNotRecentlySaved(from url: URL) {
        guard !wasSavedRecently else { return }
        load(from: url)
    }

    func save() throws {
        guard let url = fileURL else { throw DocumentError.noFileSpecified }
        lastSaveTime = Date()
        try editableContent.write(to: url, atomically: true, encoding: .utf8)
        content = editableContent
    }

    func acceptExternalUpdate() {
        if let pending = pendingExternalContent {
            content = pending
            editableContent = pending
            pendingExternalContent = nil
        }
        isExternalUpdatePending = false
    }

    func rejectExternalUpdate() {
        pendingExternalContent = nil
        isExternalUpdatePending = false
    }

    private var wasSavedRecently: Bool {
        guard let t = lastSaveTime else { return false }
        return Date().timeIntervalSince(t) < 1.0
    }

    nonisolated static func resolveFileURL(from path: String) -> Result<URL, DocumentError> {
        let url: URL
        if path.hasPrefix("/") || path.hasPrefix("~") {
            let expanded = NSString(string: path).expandingTildeInPath
            url = URL(fileURLWithPath: expanded)
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            url = URL(fileURLWithPath: cwd).appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound(url.path))
        }

        return .success(url)
    }
}

enum DocumentError: LocalizedError, Equatable {
    case fileNotFound(String)
    case noFileSpecified

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "파일을 찾을 수 없습니다: \(path)"
        case .noFileSpecified:
            return "사용법: ma <파일경로>"
        }
    }
}
