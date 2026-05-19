import Foundation

struct FileEntry: Identifiable, Equatable, Sendable {
    enum Kind: Sendable, Equatable {
        case directory
        case markdown
        case image
        case file
    }

    var id: String { url.path }

    let url: URL
    let name: String
    let kind: Kind
    let sizeBytes: Int64?
    let modifiedAt: Date?

    var isDirectory: Bool { kind == .directory }
    var isMarkdown: Bool { kind == .markdown }
    var isImage: Bool { kind == .image }

    static func isImageURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "tiff", "tif", "webp":
            return true
        default:
            return false
        }
    }
}
