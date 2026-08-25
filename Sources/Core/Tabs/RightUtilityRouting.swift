import Foundation

enum RightUtilityAction: Equatable {
    case toggleVisibility
    case select(RightSidebarTab)
    case showSnippets
    case focusSearch(SidebarSearchMode)
}

struct RightUtilityRouteState: Equatable {
    var isVisible = false
    var selectedTab: RightSidebarTab = .gitHistory

    @discardableResult
    mutating func handle(_ action: RightUtilityAction) -> SidebarSearchMode? {
        switch action {
        case .toggleVisibility:
            isVisible.toggle()
            return nil
        case .select(let tab):
            isVisible = true
            selectedTab = tab
            return nil
        case .showSnippets:
            isVisible = true
            selectedTab = .snippets
            return nil
        case .focusSearch(let mode):
            isVisible = true
            selectedTab = .fileBrowser
            return mode
        }
    }
}
