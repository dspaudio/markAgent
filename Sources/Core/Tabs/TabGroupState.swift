import Foundation

@MainActor
@Observable
final class TabGroupState {
    let id: TabGroupID
    private(set) var workingDirectory: URL?
    let gitDiffState: GitDiffState
    let gitHistoryStore: GitHistoryStore
    let timelineStore: AgentTimelineStore
    var gitUtilityMode: GitUtilityMode = .history
    var rightUtilityRoute = RightUtilityRouteState()

    init(
        id: TabGroupID = TabGroupID(),
        workingDirectory: URL? = nil,
        gitDiffState: GitDiffState = GitDiffState(),
        gitHistoryStore: GitHistoryStore = GitHistoryStore(),
        timelineStore: AgentTimelineStore = AgentTimelineStore()
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.gitDiffState = gitDiffState
        self.gitHistoryStore = gitHistoryStore
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

    func toggleRightUtility() {
        _ = rightUtilityRoute.handle(.toggleVisibility)
    }

    func selectRightUtility(_ tab: RightSidebarTab) {
        _ = rightUtilityRoute.handle(.select(tab))
    }

    func selectGitUtilityMode(_ mode: GitUtilityMode) {
        gitUtilityMode = mode
    }

    func showSnippetsSidebar() {
        _ = rightUtilityRoute.handle(.showSnippets)
    }

    func showFileBrowserSearch(_ mode: SidebarSearchMode, commandCenter: SidebarSearchCommandCenter) {
        if let focusMode = rightUtilityRoute.handle(.focusSearch(mode)) {
            commandCenter.focus(focusMode)
        }
    }

    func recordTimeline(_ action: AgentTimelineAction) {
        timelineStore.record(action)
    }
}
