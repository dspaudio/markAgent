import SwiftUI

struct TabBarView: View {
    var tabs: TabCollection
    var onNewTab: () -> Void
    var isDiffEnabled = false
    var isDiffVisible = false
    var onToggleDiff: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.tabs, id: \.id) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tabs.activeTabID == tab.id,
                            onSelect: {
                                tabs.selectTab(id: tab.id)
                            },
                            onClose: {
                                Task {
                                    await tabs.closeTab(id: tab.id)
                                }
                            }
                        )

                        Divider()
                            .frame(height: 16)
                    }
                }
            }
            
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("새 탭")
            
            Spacer()

            Button(action: onToggleDiff) {
                Label("Diff", systemImage: isDiffVisible ? "sidebar.right" : "arrow.left.arrow.right.circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(!isDiffEnabled)
            .help(isDiffEnabled ? "Git 변경 파일 보기" : "Git 저장소에서만 사용할 수 있습니다")
        }
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .overlay(
            Divider().overlay(appColors?.border ?? Color.clear),
            alignment: .bottom
        )
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
}
