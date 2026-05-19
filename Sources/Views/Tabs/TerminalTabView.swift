import GhosttyTerminal
import SwiftUI

struct TerminalTabView: NSViewRepresentable {
    var state: TerminalTabState
    var isActive: Bool

    func makeNSView(context: Context) -> AppTerminalView {
        let view = AppTerminalView()
        view.controller = state.terminalViewState.controller
        view.configuration = state.terminalViewState.configuration
        view.delegate = context.coordinator
        context.coordinator.observeState(state)
        state.terminalView = view

        state.startIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard isActive else { return }
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: AppTerminalView, context: Context) {
        nsView.controller = state.terminalViewState.controller
        nsView.configuration = state.terminalViewState.configuration

        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
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
            let url = URL(fileURLWithPath: path)
            state?.workingDirectory = url
            state?.onDirectoryChanged?(url)
        }
    }
}
