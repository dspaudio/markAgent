import Foundation

@MainActor
@Observable
final class MarkdownTab: MarkAgentTab {
    let id: UUID
    let kind: TabKind = .markdown
    let state: MarkdownTabState
    var title: String { state.title }
    var isClosable: Bool { true }
    var fileURL: URL? { state.fileURL }
    weak var dirtyPrompter: DirtyDocumentPrompting?

    var isDirty: Bool {
        state.isDirty
    }

    init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        state: MarkdownTabState? = nil,
        dirtyPrompter: DirtyDocumentPrompting? = nil
    ) {
        self.id = id
        self.state = state ?? MarkdownTabState(id: id, fileURL: fileURL)
        self.dirtyPrompter = dirtyPrompter
    }

    func prepareForClose() async -> Bool {
        await state.prepareForClose(prompt: dirtyPrompter)
    }
}
