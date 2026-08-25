import AppKit
import SwiftUI

struct TabBarView: View {
    var tabs: TabCollection
    var onNewTab: () -> Void
    var showsLeftSidebarToggle = false
    var onToggleLeftSidebar: () -> Void = {}
    var showsRightSidebarToggle = false
    var onToggleRightSidebar: () -> Void = {}

    @State private var draggedTabID: UUID?
    @State private var isCommandKeyPressed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
    var body: some View {
        HStack(spacing: 0) {
            if showsLeftSidebarToggle {
                Button(action: onToggleLeftSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.plain)
                .help(String(localized: "왼쪽 사이드바 표시"))
                .accessibilityIdentifier("sidebar.left")
                .padding(.leading, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabEntry(tab, at: index)
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

            if showsRightSidebarToggle {
                Button(action: onToggleRightSidebar) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.plain)
                .help(String(localized: "오른쪽 사이드바 표시"))
                .accessibilityIdentifier("sidebar.right")
                .padding(.trailing, 8)
            }
        }
        .frame(height: ShellChromeMetrics.headerHeight)
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .overlay(
            Divider().overlay(appColors?.border ?? Color.clear),
            alignment: .bottom
        )
        .background(groupShortcutButtons)
        .background(CommandKeyObserver(isCommandKeyPressed: $isCommandKeyPressed))
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    @ViewBuilder
    private func tabEntry(_ tab: any MarkAgentTab, at index: Int) -> some View {
        let tabID = tab.id
        let groupID = tab.groupID
        let isActiveTab = tabs.isActiveTab(id: tabID)
        let groupDepth = depthInGroup(at: index)
        let isParentActive = isFirstTab(in: groupID, at: index) && isActiveTab
        let isGroupParentActive = hasActiveParentTab(in: groupID)
        let isTuckedBehindParent = !isActiveTab && !isGroupParentActive && groupDepth > 0
        let hasNextSibling = hasNextSiblingTab(in: groupID, after: index)
        let castsTrailingShadow = hasNextSibling
            && (isParentActive || !isGroupParentActive)
        let dragValue = tabID.uuidString as NSString

        TabItemView(
            tab: tab,
            isActive: isActiveTab,
            groupShortcutNumber: tabs.groupShortcutNumber(for: groupID),
            showsGroupShortcut: isCommandKeyPressed,
            showsGroupUnderline: hasSiblingTab(in: groupID, excluding: tabID),
            isTuckedBehindParent: isTuckedBehindParent,
            castsTrailingShadow: castsTrailingShadow,
            onSelect: {
                tabs.selectTab(id: tabID)
            },
            onClose: {
                Task {
                    await tabs.closeTab(id: tabID)
                }
            }
        )
        .onDrag {
            draggedTabID = tabID
            return NSItemProvider(object: dragValue)
        }
        .onDrop(
            of: [.text],
            delegate: TabReorderDropDelegate(
                targetTabID: tabID,
                draggedTabID: $draggedTabID,
                tabs: tabs
            )
        )
        .padding(.leading, isTuckedBehindParent ? -28 : 0)
        .zIndex(isTuckedBehindParent ? -Double(groupDepth) : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTuckedBehindParent)

        if !hasNextSiblingTab(in: groupID, after: index) {
            Divider()
                .frame(height: 16)
        }
    }

    private var groupShortcutButtons: some View {
        HStack {
            ForEach(1...9, id: \.self) { shortcutNumber in
                Button {
                    tabs.selectGroup(shortcutNumber: shortcutNumber)
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(KeyEquivalent(Character("\(shortcutNumber)")), modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
        .frame(width: 0, height: 0)
    }

    private func hasSiblingTab(in groupID: TabGroupID?, excluding tabID: UUID) -> Bool {
        guard let groupID else { return false }
        return tabs.tabs.contains { tab in
            tab.id != tabID && tab.groupID == groupID
        }
    }

    private func depthInGroup(at index: Int) -> Int {
        guard tabs.tabs.indices.contains(index), let groupID = tabs.tabs[index].groupID else { return 0 }
        return tabs.tabs[..<index].filter { $0.groupID == groupID }.count
    }

    private func isFirstTab(in groupID: TabGroupID?, at index: Int) -> Bool {
        guard let groupID, tabs.tabs.indices.contains(index) else { return false }
        return !tabs.tabs[..<index].contains { $0.groupID == groupID }
    }

    private func hasActiveParentTab(in groupID: TabGroupID?) -> Bool {
        guard let groupID,
              let firstGroupTab = tabs.tabs.first(where: { $0.groupID == groupID }) else {
            return false
        }
        return firstGroupTab.id == tabs.activeTabID
    }

    private func hasNextSiblingTab(in groupID: TabGroupID?, after index: Int) -> Bool {
        guard let groupID else { return false }
        let nextIndex = tabs.tabs.index(after: index)
        guard tabs.tabs.indices.contains(nextIndex) else { return false }
        return tabs.tabs[nextIndex].groupID == groupID
    }
}

private struct CommandKeyObserver: NSViewRepresentable {
    @Binding var isCommandKeyPressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isCommandKeyPressed: $isCommandKeyPressed)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isCommandKeyPressed = $isCommandKeyPressed
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var isCommandKeyPressed: Binding<Bool>
        private var localMonitor: Any?

        init(isCommandKeyPressed: Binding<Bool>) {
            self.isCommandKeyPressed = isCommandKeyPressed
        }

        func start() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                self?.updateCommandState(from: event)
                return event
            }
        }

        func stop() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            localMonitor = nil
        }

        private func updateCommandState(from event: NSEvent) {
            let isPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if isCommandKeyPressed.wrappedValue != isPressed {
                isCommandKeyPressed.wrappedValue = isPressed
            }
        }
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
