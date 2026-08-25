import GhosttyTerminal
import SwiftUI

struct TerminalTabView: NSViewRepresentable {
    var state: TerminalTabState
    var isActive: Bool
    var isStillActive: @MainActor () -> Bool
    var onSearchShortcut: (SidebarSearchMode) -> Void = { _ in }
    var onSnippetShortcut: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> AppTerminalView {
        let view = SearchAwareTerminalView()
        view.onSearchShortcut = onSearchShortcut
        view.onSnippetShortcut = onSnippetShortcut
        view.controller = state.terminalViewState.controller
        view.configuration = state.terminalViewState.configuration
        view.delegate = context.coordinator
        view.setSurfaceVisible(isActive)
        context.coordinator.observeState(state)
        state.terminalView = view

        state.startIfNeeded()

        if isActive {
            TerminalFocusPolicy.requestFocus(view, isActive: isStillActive)
        } else {
            TerminalFocusPolicy.resignIfNeeded(view)
        }

        return view
    }

    func updateNSView(_ nsView: AppTerminalView, context: Context) {
        if let searchAwareView = nsView as? SearchAwareTerminalView {
            searchAwareView.onSearchShortcut = onSearchShortcut
            searchAwareView.onSnippetShortcut = onSnippetShortcut
        }
        if nsView.controller !== state.terminalViewState.controller {
            nsView.controller = state.terminalViewState.controller
        }
        nsView.configuration = state.terminalViewState.configuration
        if nsView.delegate !== context.coordinator {
            nsView.delegate = context.coordinator
        }
        nsView.setSurfaceVisible(isActive)
        context.coordinator.observeState(state)
        state.terminalView = nsView

        if isActive {
            TerminalFocusPolicy.requestFocus(nsView, isActive: isStillActive)
        } else {
            TerminalFocusPolicy.resignIfNeeded(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, TerminalSurfaceTitleDelegate, TerminalSurfaceCloseDelegate, TerminalSurfacePwdDelegate {
        private weak var state: TerminalTabState?

        func observeState(_ state: TerminalTabState) {
            self.state = state
        }

        func terminalDidChangeTitle(_ title: String) {
            state?.title = title
        }

        func terminalDidClose(processAlive: Bool) {
            state?.onCloseRequested?()
        }

        func terminalDidChangeWorkingDirectory(_ path: String) {
            state?.updateWorkingDirectory(path)
        }
    }
}

@MainActor
enum TerminalFocusPolicy {
    static func resignIfNeeded(_ view: NSView) {
        guard let window = view.window,
              window.firstResponder === view else {
            return
        }
        window.makeFirstResponder(nil)
    }

    static func requestFocus(
        _ view: NSView,
        isActive: @escaping @MainActor () -> Bool
    ) {
        DispatchQueue.main.async {
            guard isActive() else {
                resignIfNeeded(view)
                return
            }
            view.window?.makeFirstResponder(view)
        }
    }
}
