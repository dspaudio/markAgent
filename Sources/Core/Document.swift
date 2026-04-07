import Foundation

@Observable
@MainActor
final class MarkdownDocument {
    var content: String = ""
    var fileURL: URL?
    var errorMessage: String?
    var isLoaded: Bool = false

    func load(from url: URL) {
        do {
            content = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            errorMessage = nil
            isLoaded = true
        } catch {
            content = ""
            isLoaded = false
            errorMessage = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
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
