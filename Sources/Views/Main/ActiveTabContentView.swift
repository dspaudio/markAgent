import SwiftUI

struct ActiveTabContentView: View {
    var tabs: TabCollection
    var onOpenFile: () -> Void
    var onNewTab: () -> Void
    var onDocumentChanged: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        ZStack {
            ForEach(tabs.tabs, id: \.id) { tab in
                tabContent(for: tab, isActive: tabs.activeTabID == tab.id)
                    .opacity(tabs.activeTabID == tab.id ? 1 : 0)
            }

            if tabs.tabs.isEmpty {
                emptyStateView
            }
        }
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func tabContent(for tab: any MarkAgentTab, isActive: Bool) -> some View {
        if let terminalTab = tab as? TerminalTab {
            TerminalTabView(state: terminalTab.state, isActive: isActive)
                .onChange(of: terminalTab.state.title) { _, _ in
                    onDocumentChanged()
                }
                .onChange(of: terminalTab.state.workingDirectory) { _, _ in
                    onDocumentChanged()
                }
        } else if let markdownTab = tab as? MarkdownTab {
            MarkdownTabView(
                state: markdownTab.state,
                isActive: isActive,
                onOpenFile: onOpenFile,
                onDocumentChanged: {
                    onDocumentChanged()
                }
            )
        } else {
            Text("알 수 없는 탭 유형입니다.")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "squares.below.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("새 탭을 추가하세요")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("새 탭 만들기", action: onNewTab)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
}
