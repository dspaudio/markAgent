import SwiftUI

struct TabBarView: View {
    var tabs: TabCollection
    var onNewTab: () -> Void
    var isDiffEnabled = false
    var isDiffVisible = false
    var onToggleDiff: () -> Void = {}

    @State private var draggedTabID: UUID?
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
                    .help("새 탭")
                }
            }

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
