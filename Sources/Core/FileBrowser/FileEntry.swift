import Foundation

struct FileEntry: Identifiable, Equatable, Sendable {
    enum Kind: Sendable, Equatable {
        case directory
        case markdown
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
}
