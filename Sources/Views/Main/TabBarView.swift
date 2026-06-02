import AppKit
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
    @State private var isCommandKeyPressed = false
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
                            groupShortcutNumber: tabs.groupShortcutNumber(for: tab.groupID),
                            showsGroupShortcut: isCommandKeyPressed,
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
        .background(groupShortcutButtons)
        .background(CommandKeyObserver(isCommandKeyPressed: $isCommandKeyPressed))
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
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
