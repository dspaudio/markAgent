import Foundation

@MainActor
@Observable
final class TabCollection {
    private(set) var tabs: [any MarkAgentTab] = []
    var activeTabID: UUID?
    weak var dirtyPrompter: DirtyDocumentPrompting?

    var activeTab: (any MarkAgentTab)? {
        tabs.first { $0.id == activeTabID }
    }

    var activeTerminalTab: TerminalTab? {
        activeTab as? TerminalTab
    }

    var activeMarkdownTab: MarkdownTab? {
        activeTab as? MarkdownTab
    }

    var hasTabs: Bool { !tabs.isEmpty }

    @discardableResult
    func createTerminalTab(workingDirectory: URL, onDirectoryChanged: ((URL) -> Void)? = nil) -> TerminalTab {
        let id = UUID()
        let state = TerminalTabState(id: id, workingDirectory: workingDirectory)
        let tab = TerminalTab(id: id, workingDirectory: workingDirectory, state: state)
        state.onCloseRequested = { [weak self, weak tab] in
            guard let self, let tab else { return }
            Task {
                _ = await self.closeTab(id: tab.id)
            }
        }
        state.onDirectoryChanged = onDirectoryChanged
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    @discardableResult
    func createMarkdownTab(fileURL: URL?) -> MarkdownTab {
        let id = UUID()
        let state = MarkdownTabState(id: id, fileURL: fileURL)
        let tab = MarkdownTab(id: id, fileURL: fileURL, state: state, dirtyPrompter: dirtyPrompter)
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id
    }

    func closeTab(id: UUID) async -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let tab = tabs[index]
        guard await tab.prepareForClose() else { return false }
        tabs.remove(at: index)
        if activeTabID == id {
            activeTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
        return true
    }

    func closeActiveTab() async -> Bool {
        guard let id = activeTabID else { return false }
        return await closeTab(id: id)
    }

    func moveTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
}
