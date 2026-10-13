import AppKit
import GhosttyTerminal
import GhosttyKit
import XCTest
@testable import ma

final class TerminalLinkTests: XCTestCase {
    @MainActor
    func testPlainHomePathWithKoreanParticleOpensExistingFile() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ma-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("AGENTS.md")
        try "# Instructions".write(to: fileURL, atomically: true, encoding: .utf8)
        let homePrefix = "~/" + String(repeating: "../", count: URL(fileURLWithPath: NSHomeDirectory()).pathComponents.count - 1)
        let printedPath = homePrefix + fileURL.path.dropFirst()
        let state = TerminalTabState(workingDirectory: FileManager.default.temporaryDirectory, userConfigProvider: { nil })
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let coordinator = LinkSignalCoordinator()
        coordinator.observeState(state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 160))
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        view.delegate = coordinator
        state.terminalView = view
        view.controller = state.terminalViewState.controller
        window.contentView?.addSubview(view)
        defer {
            coordinator.onTitle = nil
            coordinator.onHover = nil
            TerminalTabView.tearDown(view, coordinator: coordinator)
            window.close()
        }
        let parsed = expectation(description: "홈 경로 출력 파싱")
        coordinator.onTitle = { if $0 == "home-path-ready" { parsed.fulfill() } }
        session.receive("\(printedPath)를 다시 읽어"
                        + "\u{1B}]2;home-path-ready\u{7}")
        await fulfillment(of: [parsed], timeout: 5)
        let metrics = try XCTUnwrap(coordinator.metrics)
        let point = view.convert(NSPoint(x: CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor * 4.5,
                                        y: view.bounds.height - CGFloat(metrics.cellHeightPixels) / window.backingScaleFactor / 2), to: nil)
        var opened: URL?
        coordinator.onOpenFile = { opened = $0 }
        coordinator.openExternalURL = { XCTFail("파일 경로가 외부 URL로 해석됨: \($0)") }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [.command],
                timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            if type == .leftMouseDown { view.mouseDown(with: event) }
            else { view.mouseUp(with: event) }
        }
        XCTAssertEqual(opened, fileURL)
        state.workingDirectory = directory
        let cjkURL = directory.appendingPathComponent("설계.md")
        try "# CJK filename".write(to: cjkURL, atomically: true, encoding: .utf8)
        for (index, entry) in [
            (fileURL.path, fileURL), ("./AGENTS.md", fileURL), ("AGENTS.md", fileURL),
            ("설계.md", cjkURL), ("설계.md를", cjkURL),
        ].enumerated() {
            let (path, expectedURL) = entry
            let ready = expectation(description: "TUI 파일 경로 출력 파싱")
            coordinator.onTitle = { if $0 == "path-ready-\(index)" { ready.fulfill() } }
            session.receive("\u{1B}[?1000h\u{1B}[?1003h\u{1B}[H\u{1B}[2J\(path)"
                            + "\u{1B}]2;path-ready-\(index)\u{7}")
            await fulfillment(of: [ready], timeout: 5)
            coordinator.onTitle = nil
            XCTAssertEqual(view.wordUnderPointer(at: view.convert(point, from: nil)), path)
            opened = nil
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [.command],
                    timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                if type == .leftMouseDown { view.mouseDown(with: event) }
                else { view.mouseUp(with: event) }
            }
            XCTAssertEqual(opened, expectedURL, path)
            let hover = try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
            view.mouseMoved(with: hover)
            XCTAssertNotNil(view.hoveredLink, path)
        }
        let blankPoint = view.convert(NSPoint(x: CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor * 70.5,
                                             y: view.bounds.height - CGFloat(metrics.cellHeightPixels) / window.backingScaleFactor / 2), to: nil)
        opened = nil
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: blankPoint, modifierFlags: [.command],
                timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            if type == .mouseMoved { view.mouseMoved(with: event) }
            else if type == .leftMouseDown { view.mouseDown(with: event) }
            else { view.mouseUp(with: event) }
        }
        XCTAssertNil(opened)
        XCTAssertNil(view.hoveredLink)
        coordinator.terminalDidRequestOpenURL("\(printedPath)와", kind: .text)
        XCTAssertEqual(opened, fileURL)
        coordinator.terminalDidRequestOpenURL("\(printedPath)은", kind: .text)
        XCTAssertEqual(opened, fileURL)

        // 조사처럼 끝나는 실제 한글 파일은 잘라내지 않는다.
        let koreanURL = directory.appendingPathComponent("AGENTS.md를")
        try "# Korean filename".write(to: koreanURL, atomically: true, encoding: .utf8)
        coordinator.terminalDidRequestOpenURL("\(printedPath)를", kind: .text)
        XCTAssertEqual(opened, koreanURL)
        coordinator.terminalDidRequestOpenURL("missing.md를", kind: .text)
        XCTAssertEqual(opened, state.workingDirectory.appendingPathComponent("missing.md를"))
    }

    @MainActor
    func testExecTerminalPropagatesHyperlinkCapabilitiesToChildShell() async throws {
        let environment = ProcessInfo.processInfo.environment
        try await assertExecHyperlinkEnvironment(
            configContents: nil,
            expectedTitle: "caps:\(environment["PI_HYPERLINKS"] ?? "1"):\(environment["FORCE_HYPERLINK"] ?? "1")"
        )
    }

    @MainActor
    func testExecTerminalPreservesExplicitHyperlinkOptOut() async throws {
        try await assertExecHyperlinkEnvironment(
            configContents: "env = PI_HYPERLINKS=0\nenv = FORCE_HYPERLINK=0",
            expectedTitle: "caps:0:0"
        )
    }

    @MainActor
    private func assertExecHyperlinkEnvironment(configContents: String?, expectedTitle: String) async throws {
        _ = NSApplication.shared
        let config = configContents.map {
            GhosttyConfig(url: URL(fileURLWithPath: "/tmp/link-capabilities-config"),
                          contents: $0, fontFamilies: [], fontSize: nil, colorTheme: nil, keybinds: [])
        }
        let state = TerminalTabState(workingDirectory: FileManager.default.temporaryDirectory,
                                     userConfigProvider: { config })
        let coordinator = LinkSignalCoordinator()
        coordinator.observeState(state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 160))
        let received = expectation(description: "자식 shell의 링크 지원 환경")
        coordinator.onTitle = {
            if $0.hasPrefix("caps:") {
                XCTAssertEqual($0, expectedTitle)
                coordinator.onTitle = nil
                received.fulfill()
            }
        }
        view.configuration = TerminalSurfaceOptions(
            backend: .exec,
            command: "printf '\\033]2;caps:%s:%s\\007' \"$PI_HYPERLINKS\" \"$FORCE_HYPERLINK\"; exec /bin/cat"
        )
        view.delegate = coordinator
        state.terminalView = view
        view.controller = state.terminalViewState.controller
        window.contentView?.addSubview(view)
        defer {
            coordinator.onTitle = nil
            TerminalTabView.tearDown(view, coordinator: coordinator)
            view.removeFromSuperview()
            window.close()
        }
        await fulfillment(of: [received], timeout: 5)
    }

    @MainActor
    func testActualGhosttyPRLinkWithTUIMouseReporting() async throws {
        _ = NSApplication.shared
        let state = TerminalTabState(workingDirectory: FileManager.default.temporaryDirectory, userConfigProvider: { nil })
        let reports = LinkMouseReports()
        let released = expectation(description: "TUI 마우스 release 보고")
        released.expectedFulfillmentCount = 1
        let session = InMemoryTerminalSession(write: {
            let report = String(decoding: $0, as: UTF8.self)
            reports.append(report)
            // host 소유 클릭은 보고하지 않고 드래그 release만 기다린다.
            if report.hasPrefix("\u{1B}[<"), report.hasSuffix("m"),
               reports.values.filter({ $0.hasPrefix("\u{1B}[<") && $0.hasSuffix("m") }).count == 1 {
                released.fulfill()
            }
        }, resize: { _ in })
        let coordinator = LinkSignalCoordinator()
        coordinator.observeState(state)
        let window = MarkAgentWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 160),
                                     styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 160))
        let viewportReady = expectation(description: "테스트 창 viewport 크기 적용")
        coordinator.onResize = {
            if $0.widthPixels == UInt32(view.bounds.width * window.backingScaleFactor),
               $0.heightPixels == UInt32(view.bounds.height * window.backingScaleFactor) {
                coordinator.onResize = nil
                viewportReady.fulfill()
            }
        }
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        view.delegate = coordinator
        state.terminalView = view
        view.controller = state.terminalViewState.controller
        window.contentView?.addSubview(view)
        defer {
            coordinator.onTitle = nil
            coordinator.onHover = nil
            coordinator.onResize = nil
            coordinator.onShape = nil
            NSCursor.arrow.set()
            TerminalTabView.tearDown(view, coordinator: coordinator)
            view.removeFromSuperview()
            window.close()
        }
        await fulfillment(of: [viewportReady], timeout: 5)

        let links = [
            ("https://github.com/comento/comento-admin-laravel/pull/4207", "Laravel #4207", 13),
            ("https://github.com/comento/comento-admin-vue/pull/1423", "Vue #1423", 9),
            ("https://example.com/hover", "한 글", 5),
        ]
        let parsed = expectation(description: "TUI 링크와 마우스 모드 파싱")
        coordinator.onTitle = { if $0 == "tui-link-ready" { parsed.fulfill() } }
        session.receive("\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1003h\u{1B}[?1006h"
                        + "\u{1B}]22;crosshair\u{7}"
                        + links.map { "\u{1B}]8;;\($0.0)\u{1B}\\\($0.1)\u{1B}[K\u{1B}]8;;\u{1B}\\" }.joined(separator: "\r\n")
                        + "\u{1B}]2;tui-link-ready\u{7}")
        await fulfillment(of: [parsed], timeout: 5)
        coordinator.onTitle = nil
        XCTAssertTrue(view.isMouseCaptured)
        let metrics = try XCTUnwrap(coordinator.metrics)
        var openedURLs: [String] = []
        for (row, link) in links.enumerated() {
            let url = link.0
            let point = view.convert(NSPoint(x: CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor * (row == 2 ? 2.5 : 0.5),
                                            y: view.bounds.height - CGFloat(metrics.cellHeightPixels) / window.backingScaleFactor * (CGFloat(row) + 0.5)), to: nil)
            let hover = try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
            view.mouseMoved(with: hover)
            XCTAssertEqual(view.hoveredLink, url)
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
            let underline = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
            let underlineBounds = try XCTUnwrap(underline.path?.boundingBox)
            XCTAssertEqual(underlineBounds.width,
                           CGFloat(link.2) * CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor,
                           accuracy: 1 / window.backingScaleFactor)
            coordinator.onHover = nil
            let opened = expectation(description: "TUI PR 링크 열기")
            coordinator.openExternalURL = {
                openedURLs.append($0.absoluteString)
                XCTAssertEqual($0.absoluteString, url)
                opened.fulfill()
            }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [.command],
                    timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                if type == .leftMouseDown { view.mouseDown(with: event) }
                else { view.mouseUp(with: event) }
            }
            await fulfillment(of: [opened], timeout: 5)
            let completed = expectation(description: "host 클릭 뒤 파서 장벽")
            coordinator.onTitle = { if $0 == "host-click-\(row)" { completed.fulfill() } }
            session.receive("\u{1B}]2;host-click-\(row)\u{7}")
            await fulfillment(of: [completed], timeout: 5)
            coordinator.onTitle = nil
            XCTAssertEqual(openedURLs, Array(links.prefix(row + 1).map(\.0)))
            XCTAssertFalse(reports.values.contains { $0.hasPrefix("\u{1B}[<0;") })
        }
        coordinator.openExternalURL = { _ in XCTFail("TUI 드래그는 링크를 열면 안 된다.") }
        let dragY = view.bounds.height - CGFloat(metrics.cellHeightPixels) / window.backingScaleFactor * 1.5
        for (type, column) in [
            (NSEvent.EventType.leftMouseDown, 0.5),
            (.leftMouseDragged, 3.5),
            (.leftMouseUp, 3.5),
        ] {
            let point = view.convert(NSPoint(x: CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor * column,
                                            y: dragY), to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        await fulfillment(of: [released], timeout: 5)
        let dragCompleted = expectation(description: "드래그 뒤 파서 장벽")
        coordinator.onTitle = { if $0 == "drag-complete" { dragCompleted.fulfill() } }
        session.receive("\u{1B}]2;drag-complete\u{7}")
        await fulfillment(of: [dragCompleted], timeout: 5)
        coordinator.onTitle = nil
        XCTAssertEqual(reports.values.filter { $0.hasPrefix("\u{1B}[<") }, [
            "\u{1B}[<35;1;1M",
            "\u{1B}[<35;1;2M",
            "\u{1B}[<35;3;3M",
            "\u{1B}[<35;1;2M",
            "\u{1B}[<0;1;2M", "\u{1B}[<32;4;2M", "\u{1B}[<0;4;2m",
        ])

        let linkPoint = view.convert(NSPoint(
            x: CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor / 2,
            y: view.bounds.height - CGFloat(metrics.cellHeightPixels) / window.backingScaleFactor / 2
        ), to: nil)
        for _ in 0..<2 {
            view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: linkPoint, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0
            )))
        }
        XCTAssertEqual(view.hoveredLink, links[0].0)
        coordinator.onHover = nil
        coordinator.openExternalURL = { _ in XCTFail("링크 밖 클릭은 마지막 호버 링크를 열면 안 된다.") }
        let blankPoint = view.convert(NSPoint(x: 400, y: 80), to: nil)
        let settled = expectation(description: "빈 칸 이동 후 엔진 이벤트 처리")
        coordinator.onTitle = { if $0 == "blank-hover-ready" { settled.fulfill() } }
        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: blankPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        )))
        session.receive("\u{1B}]2;blank-hover-ready\u{7}")
        await fulfillment(of: [settled], timeout: 5)
        coordinator.onTitle = nil
        XCTAssertNil(view.hoveredLink, "빈 칸으로 이동하면 마지막 호버 링크를 해제해야 한다.")
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair, "링크 이탈 뒤 TUI가 요청한 커서를 복원해야 한다.")
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: linkPoint, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ))
            switch type {
            case .rightMouseDown: view.rightMouseDown(with: event)
            case .rightMouseUp: view.rightMouseUp(with: event)
            case .otherMouseDown: view.otherMouseDown(with: event)
            default: view.otherMouseUp(with: event)
            }
        }
        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: blankPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        )))
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair, "다른 버튼 입력도 원래 커서 요청을 바꾸면 안 된다.")
        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: linkPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        )))
        for modifiers in [NSEvent.ModifierFlags.command, []] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .flagsChanged, location: linkPoint, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55
            ))
            view.flagsChanged(with: event)
        }
        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: blankPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        )))
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair, "수정키 입력도 원래 커서 요청을 바꾸면 안 된다.")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: blankPoint, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ))
            if type == .leftMouseDown { view.mouseDown(with: event) }
            else { view.mouseUp(with: event) }
        }
        let requested = expectation(description: "링크 hover 중 새 OSC 22 요청")
        coordinator.onShape = {
            if $0 == GHOSTTY_MOUSE_SHAPE_TEXT {
                coordinator.onShape = nil
                requested.fulfill()
            }
        }
        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: linkPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        )))
        session.receive("\u{1B}]22;text\u{7}")
        await fulfillment(of: [requested], timeout: 5)
        XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: blankPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        )))
        XCTAssertEqual(NSCursor.current, NSCursor.iBeam, "링크 hover 중 변경된 원래 요청도 복원해야 한다.")

        func event(_ type: NSEvent.EventType, _ point: NSPoint,
                   _ modifiers: NSEvent.ModifierFlags = [], _ count: Int = 1) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1
            ))
        }
        func settle(_ title: String, prefix: String = "") async {
            let completed = expectation(description: title)
            coordinator.onTitle = { if $0 == title { completed.fulfill() } }
            session.receive(prefix + "\u{1B}]2;\(title)\u{7}")
            await fulfillment(of: [completed], timeout: 5)
            coordinator.onTitle = nil
        }
        func hoverLink(_ url: String = links[0].0) throws {
            view.mouseMoved(with: try event(.mouseMoved, linkPoint))
            XCTAssertEqual(view.hoveredLink, url)
        }
        func clickFrames(since index: Int) -> [String] {
            Array(reports.values.dropFirst(index).filter { !$0.hasPrefix("\u{1B}[<35;") })
        }
        let cellBlank = view.convert(NSPoint(
            x: CGFloat(metrics.cellWidthPixels) / window.backingScaleFactor * 19.5,
            y: view.bounds.height - CGFloat(metrics.cellHeightPixels) / window.backingScaleFactor * 2.5
        ), to: nil)
        coordinator.openExternalURL = { _ in XCTFail("대조 입력은 host 링크를 열면 안 된다.") }
        view.mouseMoved(with: try event(.mouseMoved, cellBlank))
        var baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, cellBlank))
        view.mouseUp(with: try event(.leftMouseUp, cellBlank))
        await settle("blank-click-complete")
        XCTAssertEqual(clickFrames(since: baseline), ["\u{1B}[<0;20;3M", "\u{1B}[<0;20;3m"])

        for (flags, code) in [(NSEvent.ModifierFlags.option, 8), (.control, 16)] {
            try hoverLink()
            baseline = reports.values.count
            view.mouseDown(with: try event(.leftMouseDown, linkPoint, flags))
            view.mouseUp(with: try event(.leftMouseUp, linkPoint, flags))
            await settle("modifier-\(code)-complete")
            XCTAssertEqual(clickFrames(since: baseline), ["\u{1B}[<\(code);1;1M", "\u{1B}[<\(code);1;1m"])
        }
        try hoverLink()
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint))
        view.mouseUp(with: try event(.leftMouseUp, cellBlank))
        await settle("cancel-position-complete")
        XCTAssertEqual(clickFrames(since: baseline), ["\u{1B}[<0;1;1M", "\u{1B}[<32;20;3M", "\u{1B}[<0;20;3m"])

        try hoverLink()
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint))
        view.mouseUp(with: try event(.leftMouseUp, linkPoint, .option))
        await settle("cancel-modifier-complete")
        XCTAssertEqual(clickFrames(since: baseline), ["\u{1B}[<0;1;1M", "\u{1B}[<8;1;1m"])

        // 실제 Command down을 host가 캡처한 뒤 수정키 변경 또는 드래그로 취소한다.
        try hoverLink()
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint, .command))
        view.mouseUp(with: try event(.leftMouseUp, linkPoint, .option))
        await settle("command-cancel-modifier-complete")
        XCTAssertEqual(clickFrames(since: baseline), ["\u{1B}[<0;1;1M", "\u{1B}[<8;1;1m"])

        try hoverLink()
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint, .command))
        view.mouseDragged(with: try event(.leftMouseDragged, cellBlank, .command))
        view.mouseUp(with: try event(.leftMouseUp, cellBlank, .command))
        await settle("command-cancel-drag-complete")
        XCTAssertEqual(clickFrames(since: baseline), [
            "\u{1B}[<0;1;1M", "\u{1B}[<32;20;3M", "\u{1B}[<0;20;3m",
        ])

        try hoverLink()
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint))
        view.mouseExited(with: try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited, location: cellBlank, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        )))
        view.mouseDragged(with: try event(.leftMouseDragged, cellBlank))
        view.mouseDragged(with: try event(.leftMouseDragged, linkPoint))
        view.mouseUp(with: try event(.leftMouseUp, linkPoint))
        await settle("exit-drag-complete")
        XCTAssertEqual(clickFrames(since: baseline), [
            "\u{1B}[<0;1;1M", "\u{1B}[<32;20;3M", "\u{1B}[<32;1;1M", "\u{1B}[<0;1;1m",
        ])

        try hoverLink()
        var comparisonOpens: [String] = []
        coordinator.openExternalURL = { comparisonOpens.append($0.absoluteString) }
        baseline = reports.values.count
        for count in [1, 2] {
            view.mouseDown(with: try event(.leftMouseDown, linkPoint, [], count))
            view.mouseUp(with: try event(.leftMouseUp, linkPoint, [], count))
        }
        await settle("double-click-complete")
        XCTAssertEqual(comparisonOpens, [])
        XCTAssertEqual(clickFrames(since: baseline), [
            "\u{1B}[<0;1;1M", "\u{1B}[<0;1;1m", "\u{1B}[<0;1;1M", "\u{1B}[<0;1;1m",
        ])

        // 캡처 모드가 바뀌어도 down 때 선택한 host 소유권을 유지한다.
        try hoverLink()
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint, .command))
        await settle("capture-off-pending", prefix: "\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l")
        view.mouseUp(with: try event(.leftMouseUp, linkPoint, .command))
        await settle("capture-change-click-complete")
        XCTAssertEqual(comparisonOpens.count, 1)
        XCTAssertEqual(clickFrames(since: baseline), [])
        XCTAssertFalse(view.isMouseCaptured)
        for flags in [NSEvent.ModifierFlags(), .command] {
            try hoverLink()
            baseline = reports.values.count
            view.mouseDown(with: try event(.leftMouseDown, linkPoint, flags))
            view.mouseUp(with: try event(.leftMouseUp, linkPoint, flags))
            await settle("capture-off-\(flags.rawValue)-complete")
            XCTAssertEqual(clickFrames(since: baseline), [])
        }
        XCTAssertEqual(comparisonOpens, Array(repeating: links[0].0, count: 2))

        await settle("local-captured-ready", prefix: "\u{1B}[?1000h\u{1B}[?1003h\u{1B}[H\u{1B}[2J"
            + "\u{1B}]8;;docs/plan.md\u{1B}\\local\u{1B}]8;;\u{1B}\\")
        try hoverLink("docs/plan.md")
        var localFiles: [URL] = []
        coordinator.onOpenFile = { localFiles.append($0) }
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint, .command))
        view.mouseUp(with: try event(.leftMouseUp, linkPoint, .command))
        await settle("local-captured-click-complete")
        XCTAssertEqual(localFiles, [state.workingDirectory.appendingPathComponent("docs/plan.md")])
        XCTAssertEqual(comparisonOpens.count, 2)
        XCTAssertEqual(clickFrames(since: baseline), [])

        // Command 클릭 조회 직후에도 상위 휠 경로에 합성 Shift가 남지 않아야 한다.
        let scrollSelector = #selector(AppTerminalView.scrollWheel(with:))
        let scrollMethod = try XCTUnwrap(class_getInstanceMethod(AppTerminalView.self, scrollSelector))
        typealias ScrollImplementation = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        let parentScroll = unsafeBitCast(method_getImplementation(scrollMethod), to: ScrollImplementation.self)
        let wheel = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: Int32(metrics.cellHeightPixels), wheel2: 0, wheel3: 0
        ))
        wheel.flags = []
        baseline = reports.values.count
        parentScroll(view, scrollSelector, try XCTUnwrap(NSEvent(cgEvent: wheel)))
        await settle("command-click-modifiers-restored")
        XCTAssertEqual(Array(reports.values.dropFirst(baseline)), ["\u{1B}[<64;1;1M"])

        try hoverLink("docs/plan.md")
        baseline = reports.values.count
        view.mouseDown(with: try event(.leftMouseDown, linkPoint, .command))
        view.isActiveTerminal = { false }
        view.mouseUp(with: try event(.leftMouseUp, linkPoint, .command))
        await settle("inactive-click-complete")
        XCTAssertEqual(localFiles.count, 1)
        XCTAssertEqual(clickFrames(since: baseline), [])
        view.isActiveTerminal = { true }

        XCTAssertTrue(view.performBindingAction("toggle_mouse_reporting"))
        let disabledBaseline = reports.values.count
        try hoverLink("docs/plan.md")
        await settle("disabled-reporting-hover-complete")
        XCTAssertEqual(reports.values.count, disabledBaseline, "이미 꺼 둔 마우스 보고도 hover가 켜면 안 된다.")
        XCTAssertTrue(view.performBindingAction("toggle_mouse_reporting"))
    }

    @MainActor
    func testMouseMovementOutsideTerminalPreservesDestinationCursor() throws {
        _ = NSApplication.shared
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let inside = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: NSPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        view.mouseMoved(with: inside)
        view.updateHoverLink("https://example.com")
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: NSPoint(x: 150, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        defer { NSCursor.arrow.set() }
        NSCursor.resizeLeftRight.set()
        view.mouseMoved(with: event)
        XCTAssertEqual(NSCursor.current, NSCursor.resizeLeftRight)
        XCTAssertNil(view.hoveredLink, "경계 밖 mouseMoved도 이전 링크를 해제해야 한다.")
    }

    @MainActor
    func testLateHoverCallbackAfterExitPreservesDestinationCursor() throws {
        _ = NSApplication.shared
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let moved = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: NSPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        let exited = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited, location: NSPoint(x: 150, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        defer { NSCursor.arrow.set() }
        view.mouseMoved(with: moved)
        XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
        view.mouseExited(with: exited)
        XCTAssertEqual(NSCursor.current, NSCursor.arrow)
        view.updateHoverLink(nil)
        XCTAssertEqual(NSCursor.current, NSCursor.arrow)
        NSCursor.resizeLeftRight.set()
        view.updateHoverLink("https://example.com")
        XCTAssertEqual(NSCursor.current, NSCursor.resizeLeftRight)
        XCTAssertNil(view.hoveredLink)
        view.updateMouseShape(GHOSTTY_MOUSE_SHAPE_CROSSHAIR)
        XCTAssertEqual(NSCursor.current, NSCursor.resizeLeftRight)
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: NSPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        view.mouseEntered(with: entered)
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
        view.updateHoverLink("https://example.com")
        XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        view.updateHoverLink(nil)
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
    }

    @MainActor
    func testCoordinatorHandlesGhosttyLinkRequests() {
        let delegate: any TerminalSurfaceViewDelegate = TerminalTabView.Coordinator()
        XCTAssertNotNil(delegate as? any TerminalSurfaceOpenURLDelegate)
    }

    @MainActor
    func testLocalLinksResolveAgainstCurrentTerminalDirectoryAndReuseDocumentTab() throws {
        let suite = "TerminalLinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tabs = TabCollection(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("docs"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Plan".write(to: directory.appendingPathComponent("docs/plan one.md"), atomically: true, encoding: .utf8)
        try "# README".write(to: directory.appendingPathComponent("README.MARKDOWN"), atomically: true, encoding: .utf8)
        let terminal = tabs.createTerminalTab(workingDirectory: directory)
        let coordinator = TerminalTabView.Coordinator()
        coordinator.observeState(terminal.state)
        coordinator.onOpenFile = { tabs.createMarkdownTab(fileURL: $0) }
        var externalURLs: [URL] = []
        coordinator.openExternalURL = { externalURLs.append($0) }

        coordinator.terminalDidRequestOpenURL("docs/plan%20one.md#section", kind: .text)
        let document = try XCTUnwrap(tabs.activeMarkdownTab)
        XCTAssertEqual(document.fileURL, directory.appendingPathComponent("docs/plan one.md"))
        tabs.selectTab(id: terminal.id)
        coordinator.terminalDidRequestOpenURL(document.fileURL?.absoluteString ?? "", kind: .html)
        XCTAssertTrue(tabs.activeMarkdownTab === document)
        XCTAssertEqual(tabs.tabs.count, 2)

        terminal.state.workingDirectory = directory.appendingPathComponent("other", isDirectory: true)
        coordinator.terminalDidRequestOpenURL("../README.MARKDOWN", kind: .unknown)
        XCTAssertEqual(tabs.activeMarkdownTab?.fileURL, directory.appendingPathComponent("README.MARKDOWN"))
        var homeURL: URL?
        coordinator.onOpenFile = { homeURL = $0 }
        coordinator.terminalDidRequestOpenURL("~/notes.md", kind: .text)
        XCTAssertEqual(homeURL, URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("notes.md"))
        coordinator.terminalDidRequestOpenURL("database/migration.php", kind: .text)
        XCTAssertEqual(homeURL, directory.appendingPathComponent("other/database/migration.php"))

        coordinator.terminalDidRequestOpenURL("https://example.com/README.md", kind: .html)
        coordinator.terminalDidRequestOpenURL("https://example.com", kind: .text)
        coordinator.terminalDidRequestOpenURL("image.png", kind: .text)
        XCTAssertEqual(homeURL, directory.appendingPathComponent("other/image.png"))
        XCTAssertEqual(externalURLs.map(\.absoluteString), [
            "https://example.com/README.md", "https://example.com",
        ])
    }

    @MainActor
    func testDetachedCoordinatorReleasesFileCallbackAndTabState() {
        let coordinator = TerminalTabView.Coordinator()
        let view = SearchAwareTerminalView()
        weak var releasedState: TerminalTabState?
        do {
            let state = TerminalTabState(workingDirectory: FileManager.default.temporaryDirectory, userConfigProvider: { nil })
            releasedState = state
            coordinator.observeState(state)
            coordinator.onOpenFile = { [state] _ in state.title = "opened" }
            coordinator.detach(from: view)
            XCTAssertNil(coordinator.onOpenFile)
        }
        XCTAssertNil(releasedState)
        coordinator.openExternalURL = { _ in XCTFail("분리된 터미널은 링크를 열면 안 된다.") }
        coordinator.terminalDidRequestOpenURL("https://example.com", kind: .text)
    }

    @MainActor
    func testRelativeFileOpeningUsesHerdrEffectiveDirectory() {
        let outer = FileManager.default.temporaryDirectory.appendingPathComponent("outer", isDirectory: true)
        let pane = FileManager.default.temporaryDirectory.appendingPathComponent("herdr-pane", isDirectory: true)
        let state = TerminalTabState(workingDirectory: outer, userConfigProvider: { nil })
        let coordinator = TerminalTabView.Coordinator()
        coordinator.observeState(state)
        var opened: URL?
        coordinator.onOpenFile = { opened = $0 }
        state.applyHerdrDirectoryUpdate(.override(pane))
        state.receiveShellWorkingDirectory(outer.path)

        coordinator.terminalDidRequestOpenURL("note.md", kind: .text)

        XCTAssertEqual(opened, pane.appendingPathComponent("note.md").standardizedFileURL)
        state.close()
    }

    @MainActor
    func testActualGhosttyOSC8CommandClickOpensMarkdownAndPlainDragSelectsText() async throws {
        _ = NSApplication.shared
        let state = TerminalTabState(workingDirectory: FileManager.default.temporaryDirectory, userConfigProvider: { nil })
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let coordinator = LinkSignalCoordinator()
        coordinator.observeState(state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SearchAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 160))
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        view.delegate = coordinator
        state.terminalView = view
        view.controller = state.terminalViewState.controller
        window.contentView?.addSubview(view)
        defer {
            coordinator.onTitle = nil
            coordinator.onHover = nil
            coordinator.onShape = nil
            NSCursor.arrow.set()
            TerminalTabView.tearDown(view, coordinator: coordinator)
            view.removeFromSuperview()
            window.close()
        }

        let parsed = expectation(description: "OSC 8 링크 파싱 완료")
        coordinator.onTitle = { if $0 == "link-fixture-ready" { parsed.fulfill() } }
        session.receive("\u{1B}]8;;docs/plan.md\u{1B}\\문서 이름\u{1B}]8;;\u{1B}\\"
                        + "\u{1B}]2;link-fixture-ready\u{7}")
        await fulfillment(of: [parsed], timeout: 5)
        coordinator.onTitle = nil
        let metrics = try XCTUnwrap(coordinator.metrics)
        let opened = expectation(description: "실제 터미널 클릭으로 Markdown 열기")
        coordinator.onOpenFile = {
            XCTAssertEqual($0, state.workingDirectory.appendingPathComponent("docs/plan.md"))
            opened.fulfill()
        }
        coordinator.openExternalURL = { _ in XCTFail("로컬 Markdown은 외부 앱으로 열면 안 된다.") }
        let scale = window.backingScaleFactor
        let point = view.convert(NSPoint(x: CGFloat(metrics.cellWidthPixels) / scale,
                                        y: view.bounds.height - CGFloat(metrics.cellHeightPixels) / scale / 2), to: nil)
        let hover = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [.command],
                                                   timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        let hovered = expectation(description: "실제 Command로 링크 hover 인식")
        coordinator.onHover = { url in
            if url == "docs/plan.md" {
                coordinator.onHover = nil
                hovered.fulfill()
            }
        }
        view.mouseMoved(with: hover)
        view.mouseMoved(with: hover)
        await fulfillment(of: [hovered], timeout: 5)
        coordinator.onHover = nil
        XCTAssertEqual(view.hoveredLink, "docs/plan.md")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [.command],
                                                       timestamp: 0, windowNumber: window.windowNumber,
                                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) }
            else { view.mouseUp(with: event) }
        }
        await fulfillment(of: [opened], timeout: 5)

        coordinator.onOpenFile = { _ in XCTFail("일반 드래그는 링크를 열면 안 된다.") }
        let start = NSPoint(x: CGFloat(metrics.cellWidthPixels) / scale / 4, y: point.y)
        let end = NSPoint(x: CGFloat(metrics.cellWidthPixels) / scale * 10, y: point.y)
        for (type, location) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                       timestamp: 0, windowNumber: window.windowNumber,
                                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        let selection = TerminalSelectionPasteboardReader.readSelectedText {
            view.performBindingAction("copy_to_clipboard")
        }
        XCTAssertEqual(selection?.trimmingCharacters(in: .whitespacesAndNewlines), "문서 이름")

        let blankPoint = view.convert(NSPoint(x: 200, y: 80), to: nil)
        let blankHover = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: blankPoint, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        view.mouseMoved(with: blankHover)
        for (shape, value, cursor) in [
            ("pointer", GHOSTTY_MOUSE_SHAPE_POINTER, NSCursor.pointingHand),
            ("crosshair", GHOSTTY_MOUSE_SHAPE_CROSSHAIR, NSCursor.crosshair),
            ("default", GHOSTTY_MOUSE_SHAPE_DEFAULT, NSCursor.arrow),
            ("text", GHOSTTY_MOUSE_SHAPE_TEXT, NSCursor.iBeam),
        ] {
            let changed = expectation(description: "OSC 22 \(shape) 커서 요청 처리")
            coordinator.onShape = {
                if $0 == value {
                    coordinator.onShape = nil
                    changed.fulfill()
                }
            }
            session.receive("\u{1B}]22;\(shape)\u{7}")
            await fulfillment(of: [changed], timeout: 5)
            XCTAssertEqual(NSCursor.current, cursor)
            view.mouseMoved(with: blankHover)
            XCTAssertEqual(NSCursor.current, cursor)
        }
    }
}

private final class LinkMouseReports: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [String] = []
    private var buffer = ""

    var values: [String] {
        lock.withLock { reports }
    }

    func append(_ report: String) {
        lock.withLock {
            buffer += report
            while let start = buffer.range(of: "\u{1B}[<"),
                  let end = buffer[start.upperBound...].firstIndex(where: { $0 == "M" || $0 == "m" }) {
                reports.append(String(buffer[start.lowerBound...end]))
                buffer.removeSubrange(...end)
            }
        }
    }
}

@MainActor
private final class LinkSignalCoordinator: TerminalTabView.Coordinator, TerminalSurfaceGridResizeDelegate {
    var onTitle: ((String) -> Void)?
    var onHover: ((String?) -> Void)?
    var onShape: ((ghostty_action_mouse_shape_e) -> Void)?
    var onResize: ((TerminalGridMetrics) -> Void)?
    var metrics: TerminalGridMetrics?

    override func terminalDidChangeTitle(_ title: String) {
        super.terminalDidChangeTitle(title)
        onTitle?(title)
    }

    func terminalDidResize(_ size: TerminalGridMetrics) {
        metrics = size
        onResize?(size)
    }

    override func terminalDidUpdateHoverLink(_ url: String?) {
        super.terminalDidUpdateHoverLink(url)
        onHover?(url)
    }

    override func terminalDidChangeMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        super.terminalDidChangeMouseShape(shape)
        onShape?(shape)
    }
}
