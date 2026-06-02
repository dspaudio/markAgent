import Foundation

@MainActor
@Observable
final class GitDiffTab: MarkAgentTab {
    let id: UUID
    let kind: TabKind = .gitDiff
    let state: GitDiffState
    let groupState: TabGroupState?
    var title: String { "Git Diff" }
    var isDirty: Bool { false }
    var isClosable: Bool { true }
    var groupID: TabGroupID? { groupState?.id }

    init(id: UUID = UUID(), state: GitDiffState, groupState: TabGroupState? = nil) {
        self.id = id
        self.state = state
        self.groupState = groupState
    }

    func prepareForClose() async -> Bool {
        true
    }
}
