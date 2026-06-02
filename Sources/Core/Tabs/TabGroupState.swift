import Foundation

@MainActor
@Observable
final class TabGroupState {
    let id: TabGroupID
    private(set) var workingDirectory: URL?
    let gitDiffState: GitDiffState
    let timelineStore: AgentTimelineStore
    var rightSidebarTab: RightSidebarTab = .gitChanges

    init(
        id: TabGroupID = TabGroupID(),
        workingDirectory: URL? = nil,
        gitDiffState: GitDiffState = GitDiffState(),
        timelineStore: AgentTimelineStore = AgentTimelineStore()
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.gitDiffState = gitDiffState
        self.timelineStore = timelineStore
    }

    func updateWorkingDirectory(_ url: URL?) {
        workingDirectory = url?.standardizedFileURL
        if let workingDirectory {
            gitDiffState.refresh(for: workingDirectory)
        }
    }

    func syncTimelineToGitRepository() {
        timelineStore.configureRepositoryRoot(gitDiffState.repositoryRoot)
    }

    func recordTimeline(_ action: AgentTimelineAction) {
        timelineStore.record(action)
    }
}
