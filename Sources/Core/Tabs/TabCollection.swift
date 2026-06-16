import Foundation

@MainActor
@Observable
final class TabCollection {
    private(set) var tabs: [any MarkAgentTab] = []
    private(set) var tabGroups: [TabGroupID: TabGroupState] = [:]
    var activeTabID: UUID?
    private var lastActiveGroupID: TabGroupID?
    weak var dirtyPrompter: DirtyDocumentPrompting?

    var activeTab: (any MarkAgentTab)? {
        tabs.first { $0.id == activeTabID }
    }

    var activeTerminalTab: TerminalTab? {
        activeTab as? TerminalTab
    }

    var activeTabGroup: TabGroupState? {
        if let groupID = activeTab?.groupID {
            return tabGroups[groupID]
        }
        if let lastActiveGroupID {
            return tabGroups[lastActiveGroupID]
        }
        return nil
    }

    var activeMarkdownTab: MarkdownTab? {
        activeTab as? MarkdownTab
    }

    var activeGitDiffTab: GitDiffTab? {
        activeTab as? GitDiffTab
    }

    var activeSettingsTab: SettingsTab? {
        activeTab as? SettingsTab
    }

    var activeAboutTab: AboutTab? {
        activeTab as? AboutTab
    }

    var hasTabs: Bool { !tabs.isEmpty }

    var orderedGroupIDs: [TabGroupID] {
        var seen: Set<TabGroupID> = []
        var ordered: [TabGroupID] = []

        for tab in tabs {
            guard let groupID = tab.groupID,
                  !seen.contains(groupID) else {
                continue
            }
            seen.insert(groupID)
            ordered.append(groupID)
        }

        return ordered
    }

    func groupShortcutNumber(for groupID: TabGroupID?) -> Int? {
        guard let groupID,
              let index = orderedGroupIDs.firstIndex(of: groupID),
              index < 9 else {
            return nil
        }
        return index + 1
    }

    @discardableResult
    func createTerminalTab(workingDirectory: URL, onDirectoryChanged: ((URL) -> Void)? = nil) -> TerminalTab {
        let id = UUID()
        let groupState = TabGroupState(workingDirectory: workingDirectory)
        tabGroups[groupState.id] = groupState
        lastActiveGroupID = groupState.id
        let state = TerminalTabState(id: id, workingDirectory: workingDirectory)
        let tab = TerminalTab(id: id, workingDirectory: workingDirectory, state: state, groupState: groupState)
        state.onCloseRequested = { [weak self, weak tab] in
            guard let self, let tab else { return }
            Task {
                _ = await self.closeTab(id: tab.id)
            }
        }
        state.onDirectoryChanged = { [weak groupState] url in
            groupState?.updateWorkingDirectory(url)
            onDirectoryChanged?(url)
        }
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    @discardableResult
    func createMarkdownTab(fileURL: URL?) -> MarkdownTab {
        if let fileURL {
            let standardURL = fileURL.standardizedFileURL
            if let existingTab = tabs.compactMap({ $0 as? MarkdownTab }).first(where: {
                $0.fileURL?.standardizedFileURL == standardURL
            }) {
                activeTabID = existingTab.id
                if let groupState = existingTab.groupState {
                    lastActiveGroupID = groupState.id
                }
                return existingTab
            }
        }

        let id = UUID()
        let state = MarkdownTabState(id: id, fileURL: fileURL)
        let groupState = ensureActiveGroup(workingDirectory: fileURL?.deletingLastPathComponent())
        let tab = MarkdownTab(id: id, fileURL: fileURL, state: state, groupState: groupState, dirtyPrompter: dirtyPrompter)
        insert(tab, in: groupState)
        activeTabID = tab.id
        lastActiveGroupID = groupState.id
        return tab
    }

    @discardableResult
    func showGitDiffTab(state: GitDiffState) -> GitDiffTab {
        if let tab = tabs.first(where: { $0 is GitDiffTab }) as? GitDiffTab {
            activeTabID = tab.id
            return tab
        }

        let tab = GitDiffTab(state: state)
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    @discardableResult
    func showGitDiffTabForActiveGroup() -> GitDiffTab {
        let groupState = ensureActiveGroup()

        if let tab = tabs.first(where: { tab in
            guard let diffTab = tab as? GitDiffTab else { return false }
            return diffTab.groupState?.id == groupState.id
        }) as? GitDiffTab {
            activeTabID = tab.id
            lastActiveGroupID = groupState.id
            return tab
        }

        let tab = GitDiffTab(state: groupState.gitDiffState, groupState: groupState)
        tabs.append(tab)
        activeTabID = tab.id
        lastActiveGroupID = groupState.id
        return tab
    }

    @discardableResult
    func showSettingsTab() -> SettingsTab {
        if let tab = tabs.first(where: { $0 is SettingsTab }) as? SettingsTab {
            activeTabID = tab.id
            return tab
        }

        let tab = SettingsTab()
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    @discardableResult
    func showAboutTab() -> AboutTab {
        if let tab = tabs.first(where: { $0 is AboutTab }) as? AboutTab {
            activeTabID = tab.id
            return tab
        }

        let tab = AboutTab()
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        syncLastActiveGroupFromActiveTab()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id
        syncLastActiveGroupFromActiveTab()
    }

    @discardableResult
    func selectGroup(shortcutNumber: Int) -> Bool {
        guard (1...9).contains(shortcutNumber) else { return false }
        let groupIndex = shortcutNumber - 1
        let groupIDs = orderedGroupIDs
        guard groupIDs.indices.contains(groupIndex) else { return false }

        let groupID = groupIDs[groupIndex]
        let groupTabs = tabs.filter { $0.groupID == groupID }
        guard !groupTabs.isEmpty else { return false }

        if activeTab?.groupID == groupID,
           let currentActiveTabID = activeTabID,
           let activeGroupIndex = groupTabs.firstIndex(where: { $0.id == currentActiveTabID }) {
            let nextIndex = groupTabs.index(after: activeGroupIndex)
            activeTabID = groupTabs[nextIndex == groupTabs.endIndex ? groupTabs.startIndex : nextIndex].id
        } else {
            activeTabID = groupTabs[0].id
        }

        lastActiveGroupID = groupID
        return true
    }

    func closeTab(id: UUID) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let tab = tabs[index]
        let closedGroupID = tab.groupID
        let replacementTabID = activeTabID == id ? tabToActivateAfterClosingTab(at: index) : nil
        guard await tab.prepareForClose() else { return false }
        tabs.remove(at: index)
        removeGroupIfOrphaned(closedGroupID)
        if activeTabID == id {
            activeTabID = replacementTabID
        }
        syncLastActiveGroupFromActiveTab()
        return true
    }

    func closeActiveTab() async -> Bool {
        guard let id = activeTabID else { return false }
        return await closeTab(id: id)
    }

    func moveTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    private func ensureActiveGroup(workingDirectory: URL? = nil) -> TabGroupState {
        if let groupState = activeTabGroup {
            if let workingDirectory, groupState.workingDirectory == nil {
                groupState.updateWorkingDirectory(workingDirectory)
            }
            return groupState
        }

        let groupState = TabGroupState(workingDirectory: workingDirectory)
        tabGroups[groupState.id] = groupState
        lastActiveGroupID = groupState.id
        return groupState
    }

    private func syncLastActiveGroupFromActiveTab() {
        if let groupID = activeTab?.groupID {
            lastActiveGroupID = groupID
        } else if lastActiveGroupID.map({ tabGroups[$0] == nil }) == true {
            lastActiveGroupID = tabs.compactMap(\.groupID).first
        }
    }

    private func insert(_ tab: any MarkAgentTab, in groupState: TabGroupState) {
        guard let lastGroupIndex = tabs.lastIndex(where: { $0.groupID == groupState.id }) else {
            tabs.append(tab)
            return
        }

        tabs.insert(tab, at: tabs.index(after: lastGroupIndex))
    }

    private func tabToActivateAfterClosingTab(at closingIndex: Int) -> UUID? {
        guard tabs.indices.contains(closingIndex) else { return nil }

        if let groupID = tabs[closingIndex].groupID {
            if let previousGroupTab = tabs[..<closingIndex].last(where: { $0.groupID == groupID }) {
                return previousGroupTab.id
            }

            let nextIndex = tabs.index(after: closingIndex)
            if nextIndex < tabs.endIndex,
               let nextGroupTab = tabs[nextIndex...].first(where: { $0.groupID == groupID }) {
                return nextGroupTab.id
            }
        }

        let nextIndex = tabs.index(after: closingIndex)
        if tabs.indices.contains(nextIndex) {
            return tabs[nextIndex].id
        }

        return tabs[..<closingIndex].last?.id
    }

    private func removeGroupIfOrphaned(_ groupID: TabGroupID?) {
        guard let groupID else { return }
        guard !tabs.contains(where: { $0.groupID == groupID }) else { return }
        tabGroups[groupID] = nil
        if lastActiveGroupID == groupID {
            lastActiveGroupID = tabs.compactMap(\.groupID).last
        }
    }
}
