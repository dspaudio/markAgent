import SwiftUI

struct TabBarView: View {
    var tabs: TabCollection
    var onNewTab: () -> Void
    var isLeftSidebarVisible = true
    var onToggleLeftSidebar: () -> Void = {}
    var isDiffEnabled = false
    var isDiffVisible = false
    var onToggleDiff: () -> Void = {}

    @State private var draggedTabID: UUID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleLeftSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLeftSidebarVisible ? (appColors?.accent ?? Color.accentColor) : (appColors?.foreground ?? Color.primary))
            .help(isLeftSidebarVisible ? String(localized: "왼쪽 사이드바 숨기기") : String(localized: "왼쪽 사이드바 표시"))
            .padding(.leading, 8)

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
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: TabReorderDropDelegate(
                                targetTabID: tab.id,
                                draggedTabID: $draggedTabID,
                                tabs: tabs
                            )
                        )

                        Divider()
                            .frame(height: 16)
                    }

                    Button(action: onNewTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
                    .help(String(localized: "새 탭"))
                }
            }

            Spacer()

            Button(action: onToggleDiff) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isDiffVisible
                ? (appColors?.accent ?? Color.accentColor)
                : (appColors?.foreground ?? Color.primary)
            )
            .help(isDiffVisible ? String(localized: "오른쪽 사이드바 숨기기") : String(localized: "오른쪽 사이드바 표시"))
            .padding(.trailing, 8)
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

private struct TabReorderDropDelegate: DropDelegate {
    let targetTabID: UUID
    @Binding var draggedTabID: UUID?
    var tabs: TabCollection

    func dropEntered(info: DropInfo) {
        guard let draggedTabID,
              draggedTabID != targetTabID,
              let sourceIndex = tabs.tabs.firstIndex(where: { $0.id == draggedTabID }),
              let targetIndex = tabs.tabs.firstIndex(where: { $0.id == targetTabID }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            tabs.moveTab(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [.text]) {
            draggedTabID = nil
        }
    }
}
