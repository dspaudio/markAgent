import Foundation

@MainActor
@Observable
final class GitDiffTab: MarkAgentTab {
    let id: UUID
    let kind: TabKind = .gitDiff
    let state: GitDiffState
    var title: String { "Git Diff" }
    var isDirty: Bool { false }
    var isClosable: Bool { true }

    init(id: UUID = UUID(), state: GitDiffState) {
        self.id = id
        self.state = state
    }

    func prepareForClose() async -> Bool {
        true
    }
}
