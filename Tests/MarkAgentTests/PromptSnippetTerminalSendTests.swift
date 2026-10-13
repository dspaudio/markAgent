import AppKit
import GhosttyTerminal
import XCTest
@testable import ma

final class PromptSnippetTerminalSendTests: XCTestCase {
    @MainActor
    func testSendPastesFullBodyIntoActiveTerminalWithoutEnterAndFocusesIt() async throws {
        _ = NSApplication.shared
        let suite = "PromptSnippetTerminalSendTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tabs = TabCollection(defaults: defaults)
        let terminal = tabs.createTerminalTab(workingDirectory: FileManager.default.temporaryDirectory)
        let state = terminal.state
        let writes = PtyWriteCapture()
        let session = InMemoryTerminalSession(write: { writes.append($0) }, resize: { _ in })
        let coordinator = TitleSignalCoordinator()
        coordinator.observeState(state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 160))
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        view.delegate = coordinator
        view.connectSearch(state.search)
        state.terminalView = view
        view.controller = state.terminalViewState.controller
        window.contentView?.addSubview(view)
        defer {
            coordinator.onTitle = nil
            TerminalTabView.tearDown(view, coordinator: coordinator)
            view.removeFromSuperview()
            window.close()
            state.close()
        }

        // 앱이 브라켓 붙여넣기 모드를 켠 상태를 만들고, 마지막 OSC 제목 콜백으로 파싱 완료를 확인한다.
        let ready = expectation(description: "bracketed paste mode parsed")
        coordinator.onTitle = { if $0 == "send-fixture-ready" { ready.fulfill() } }
        session.receive("\u{1B}[?2004h\u{1B}]2;send-fixture-ready\u{7}")
        await fulfillment(of: [ready], timeout: 5)
        coordinator.onTitle = nil

        let body = "첫 줄 프롬프트\n  second line with `code`\n\n마지막 줄"
        let date = Date(timeIntervalSince1970: 0)
        let snippet = PromptSnippet(id: UUID(), body: body, createdAt: date, updatedAt: date)
        let pasted = expectation(description: "bracketed paste reached the pty")
        writes.fulfill(pasted, whenTextHasSuffix: "\u{1B}[201~")

        XCTAssertTrue(MainContainerView.sendSnippetToActiveTerminal(snippet, in: tabs))
        await fulfillment(of: [pasted], timeout: 5)
        XCTAssertEqual(writes.text, "\u{1B}[200~" + body + "\u{1B}[201~")

        // 포커스 요청은 다음 런루프에서 적용되므로 같은 큐에 뒤이어 넣은 블록으로 완료를 기다린다.
        let focused = expectation(description: "deferred terminal focus applied")
        DispatchQueue.main.async { focused.fulfill() }
        await fulfillment(of: [focused], timeout: 1)
        XCTAssertTrue(window.firstResponder === view)
    }

    @MainActor
    func testSendIsNoOpWithoutAttachedActiveTerminal() throws {
        let suite = "PromptSnippetTerminalSendTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tabs = TabCollection(defaults: defaults)
        let date = Date(timeIntervalSince1970: 0)
        let snippet = PromptSnippet(id: UUID(), body: "echo hi", createdAt: date, updatedAt: date)

        XCTAssertFalse(MainContainerView.sendSnippetToActiveTerminal(snippet, in: tabs))

        let terminal = tabs.createTerminalTab(workingDirectory: FileManager.default.temporaryDirectory)
        defer { terminal.state.close() }
        XCTAssertNil(terminal.state.terminalView)
        XCTAssertFalse(MainContainerView.sendSnippetToActiveTerminal(snippet, in: tabs))
    }
}

/// 호스트 관리 백엔드가 pty로 받은 바이트를 모은다. 쓰기 콜백은 메인 스레드 밖에서 올 수 있다.
private final class PtyWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var pending: (suffix: String, expectation: XCTestExpectation)?

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }

    func fulfill(_ expectation: XCTestExpectation, whenTextHasSuffix suffix: String) {
        lock.lock()
        pending = (suffix, expectation)
        lock.unlock()
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var matched: XCTestExpectation?
        if let pending, String(decoding: buffer, as: UTF8.self).hasSuffix(pending.suffix) {
            matched = pending.expectation
            self.pending = nil
        }
        lock.unlock()
        matched?.fulfill()
    }
}

@MainActor
private final class TitleSignalCoordinator: TerminalTabView.Coordinator {
    var onTitle: ((String) -> Void)?

    override func terminalDidChangeTitle(_ title: String) {
        super.terminalDidChangeTitle(title)
        onTitle?(title)
    }
}
