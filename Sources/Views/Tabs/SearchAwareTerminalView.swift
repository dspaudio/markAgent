import AppKit
import GhosttyTerminal
import GhosttyKit

final class SearchAwareTerminalView: AppTerminalView {
    var onSearchShortcut: ((SidebarSearchMode) -> Void)?
    var onSnippetShortcut: ((String) -> Void)?
    var selectedTextProvider: (() -> String?)?
    var isActiveTerminal: @MainActor () -> Bool = { true }
    private(set) weak var searchState: TerminalSearchState?
    private(set) var searchBar: TerminalSearchBar?
    private(set) var hoveredLink: String?
    private var detectedLink: String?
    private let hoverUnderline = CAShapeLayer()
    private var pendingLinkClick: (url: String, down: NSEvent, captured: Bool)?
    private var isPointerInside = false
    private var requestedCursor = NSCursor.iBeam
    private var isHandlingPointerEvent = false

    private func withPointerUpdate(_ action: () -> Void) {
        let previous = isHandlingPointerEvent
        isHandlingPointerEvent = true
        defer { isHandlingPointerEvent = previous }
        action()
    }

    override func mouseDown(with event: NSEvent) {
        clearHover()
        if let pending = pendingLinkClick, pending.captured {
            pendingLinkClick = nil
            if isActiveTerminal() {
                withPointerUpdate { super.mouseDown(with: pending.down) }
            }
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        pendingLinkClick = nil
        if isActiveTerminal(), modifiers == [.command], event.clickCount == 1,
           let url = commandClickLink(with: event) {
            pendingLinkClick = (url, event, true)
            window?.makeFirstResponder(self)
            return
        }
        withPointerUpdate { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        clearHover()
        let pending = pendingLinkClick
        pendingLinkClick = nil
        if pending?.captured == true, !isActiveTerminal() { return }
        withPointerUpdate {
            if let pending, pending.captured { super.mouseDown(with: pending.down) }
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pending = pendingLinkClick
        pendingLinkClick = nil
        if pending?.captured == true, !isActiveTerminal() { return }
        let opensLink = pending != nil && isActiveTerminal()
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command]
            && pending?.down.locationInWindow == event.locationInWindow
            && pending?.url == commandClickLink(with: event)
        withPointerUpdate {
            if let pending, pending.captured {
                if !opensLink {
                    super.mouseDown(with: pending.down)
                    super.mouseUp(with: event)
                }
            } else {
                super.mouseUp(with: event)
            }
        }
        guard opensLink, let pending else { return }
        (delegate as? any TerminalSurfaceOpenURLDelegate)?.terminalDidRequestOpenURL(pending.url, kind: .unknown)
    }

    override func scrollWheel(with event: NSEvent) {
        clearHover()
        withPointerUpdate {
            invalidateMousePosition()
            super.mouseMoved(with: event)
            super.scrollWheel(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        withPointerUpdate { super.rightMouseDown(with: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        withPointerUpdate { super.rightMouseUp(with: event) }
    }

    override func otherMouseDown(with event: NSEvent) {
        withPointerUpdate { super.otherMouseDown(with: event) }
    }

    override func otherMouseUp(with event: NSEvent) {
        withPointerUpdate { super.otherMouseUp(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        withPointerUpdate { super.flagsChanged(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        withPointerUpdate { super.keyUp(with: event) }
    }

    func updateHoverLink(_ url: String?) {
        detectedLink = url
        guard !isHandlingPointerEvent else { return }
        guard isActiveTerminal(), isPointerInside else {
            clearHover()
            return
        }
        hoveredLink = url
        if url == nil { hoverUnderline.path = nil }
        updatePointerCursor()
    }

    private func probeLink(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> String? {
        detectedLink = nil
        invalidateMousePosition(modifiers: modifiers)
        updateMousePosition(at: point, modifiers: modifiers)
        if let detectedLink { return detectedLink }
        guard let word = wordUnderPointer(at: point) else { return nil }
        return (delegate as? TerminalTabView.Coordinator)?.existingFileLink(word)
    }

    private func commandClickLink(with event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil)
        isPointerInside = bounds.contains(point)
        guard isPointerInside else { return nil }
        var url: String?
        withPointerUpdate {
            var modifiers = event.modifierFlags
            if isMouseCaptured { modifiers.insert(.shift) }
            // TUI 캡처 우회는 실제 Command 클릭 동안만 수행한다.
            // NSEvent를 합성하지 않고, 동기 콜백의 URL을 저장한 뒤 실제 수정키를 복원한다.
            url = probeLink(at: point, modifiers: modifiers)
            invalidateMousePosition(modifiers: event.modifierFlags)
            super.mouseMoved(with: event)
        }
        updatePointerCursor()
        return url
    }

    func updateMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        // 입력 중 엔진이 보내는 링크용 커서는 프로그램의 OSC 22 요청이 아니다.
        guard !isHandlingPointerEvent else { return }
        requestedCursor = Self.cursor(for: shape)
        updatePointerCursor()
    }

    private func updatePointerCursor() {
        guard isActiveTerminal(), isPointerInside else { return }
        (hoveredLink == nil ? requestedCursor : NSCursor.pointingHand).set()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        refreshHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // 상위 뷰의 드래그 처리도 이 메서드를 호출하므로 선택 중에는 수정키를 바꾸지 않는다.
        guard event.type == .mouseMoved else {
            withPointerUpdate { super.mouseMoved(with: event) }
            return
        }
        refreshHover(with: event)
    }

    private func refreshHover(with event: NSEvent) {
        clearHover()
        // first responder에는 터미널 밖의 이동도 전달되므로 다른 영역의 커서를 덮어쓰지 않는다.
        let point = convert(event.locationInWindow, from: nil)
        isPointerInside = bounds.contains(point)
        guard isActiveTerminal(), isPointerInside else { return }
        var link: String?
        var rectangles: [NSRect] = []
        withPointerUpdate {
            let captured = isMouseCaptured
            var modifiers = event.modifierFlags.union(.command)
            if captured { modifiers.insert(.shift) }
            var querying = false
            defer {
                // 조회 성공·실패와 무관하게 실제 좌표·수정키를 복원한다.
                if querying {
                    invalidateMousePosition(modifiers: modifiers)
                    setHoverQueryActive(false, modifiers: modifiers)
                }
                invalidateMousePosition(modifiers: event.modifierFlags)
                super.mouseMoved(with: event)
            }
            // 실제 이동을 먼저 보고하여 같은 셀의 URL 조회가 별도 이동으로 기록되지 않게 한다.
            super.mouseMoved(with: event)
            guard let url = probeLink(at: point, modifiers: modifiers) else { return }
            if captured {
                setHoverQueryActive(true, modifiers: modifiers)
                querying = true
            }
            rectangles = hoverLinkRects(at: point) { candidate in
                probeLink(at: candidate, modifiers: modifiers) == url
            }
            if !rectangles.isEmpty { link = url }
        }
        hoveredLink = link
        if !rectangles.isEmpty {
            let path = CGMutablePath()
            rectangles.forEach { path.addRect($0) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hoverUnderline.frame = bounds
            hoverUnderline.contentsScale = window?.backingScaleFactor ?? 1
            effectiveAppearance.performAsCurrentDrawingAppearance {
                hoverUnderline.fillColor = NSColor.linkColor.cgColor
            }
            hoverUnderline.path = path
            if hoverUnderline.superlayer == nil { layer?.addSublayer(hoverUnderline) }
            CATransaction.commit()
        }
        updatePointerCursor()
    }

    private func clearHover() {
        hoveredLink = nil
        hoverUnderline.path = nil
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        withPointerUpdate { super.mouseExited(with: event) }
        invalidateMousePosition(modifiers: event.modifierFlags)
        clearHover()
        NSCursor.arrow.set()
    }

    func connectSearch(_ state: TerminalSearchState) {
        guard searchState !== state else { return }
        searchState?.disconnect()
        searchState = state
        state.connect(
            performAction: { [weak self] in self?.performBindingAction($0) ?? false },
            onChange: { [weak self, weak state] in
                guard let state else { return }
                self?.searchBar?.update(from: state)
            }
        )
    }

    func presentTerminalSearch() {
        guard isActiveTerminal(), let searchState else { return }
        if searchBar == nil {
            let bar = TerminalSearchBar(frame: NSRect(x: 0, y: 0, width: 440, height: 40))
            bar.terminalView = self
            addSubview(bar)
            searchBar = bar
        }
        searchState.present()
        layoutSearchBar()
        searchBar?.focus()
    }

    override func layout() {
        super.layout()
        if hoverUnderline.frame != bounds { clearHover() }
        layoutSearchBar()
    }

    private func layoutSearchBar() {
        guard let searchBar, !bounds.isEmpty else { return }
        // 부모에 제약을 연결하면 검색창의 최소 폭이 터미널 viewport까지 넓힌다.
        let width = min(440, max(0, bounds.width - 16))
        let height = searchBar.fittingSize.height
        searchBar.frame = NSRect(
            x: bounds.maxX - width - 8,
            y: isFlipped ? bounds.minY + 8 : bounds.maxY - height - 8,
            width: width,
            height: height
        )
        searchBar.layoutSubtreeIfNeeded()
    }

    func dismissTerminalSearch(restoringFocus: Bool = true) {
        searchState?.dismiss()
        if restoringFocus, isActiveTerminal() {
            window?.makeFirstResponder(self)
        }
    }

    func disconnectSearch() {
        isPointerInside = false
        clearHover()
        hoverUnderline.removeFromSuperlayer()
        pendingLinkClick = nil
        searchState?.disconnect()
        searchState = nil
        searchBar?.terminalView = nil
        searchBar?.searchField.delegate = nil
        searchBar?.removeFromSuperview()
        searchBar = nil
        isActiveTerminal = { false }
    }

    @discardableResult
    func handleTerminalSearchShortcut(_ event: NSEvent) -> Bool {
        guard isActiveTerminal(), searchState != nil else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command], key == "f" {
            presentTerminalSearch()
            return true
        }
        guard searchState?.isPresented == true else { return false }
        if key == "g", modifiers == [.command] {
            searchState?.navigate(backwards: false)
            return true
        }
        if event.keyCode == 53, modifiers.isEmpty {
            dismissTerminalSearch()
            return true
        }
        return false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActiveTerminal() else { return false }
        if handleTerminalSearchShortcut(event) { return true }
        if handleSnippetShortcut(event) {
            return true
        }
        if handleSearchShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        clearHover()
        if handleTerminalSearchShortcut(event) { return }
        if handleSnippetShortcut(event) {
            return
        }
        if handleSearchShortcut(event) {
            return
        }
        withPointerUpdate { super.keyDown(with: event) }
    }

    private func handleSearchShortcut(_ event: NSEvent) -> Bool {
        guard let mode = sidebarSearchMode(for: event) else { return false }
        onSearchShortcut?(mode)
        return true
    }

    private func handleSnippetShortcut(_ event: NSEvent) -> Bool {
        guard isSnippetShortcut(event) else { return false }
        guard let selectedText = selectedTextForSnippet(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return true
        }

        onSnippetShortcut?(selectedText)
        return true
    }

    private func isSnippetShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }

        return key == "c"
    }

    private func selectedTextForSnippet() -> String? {
        if let selectedTextProvider {
            return selectedTextProvider()
        }

        return TerminalSelectionPasteboardReader.readSelectedText {
            performBindingAction("copy_to_clipboard")
        }
    }

    private func sidebarSearchMode(for event: NSEvent) -> SidebarSearchMode? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return nil }

        switch key {
        case "f":
            return .files
        case "g":
            return .grep
        default:
            return nil
        }
    }
}
