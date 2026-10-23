import AppKit
import WebKit
import XCTest
import Observation
import SwiftUI
@testable import ma

final class EditorWebViewTests: XCTestCase {
    static let assetURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/App/Resources/Editor/index.html")

    @MainActor
    func testRawSyntaxRangesSurviveMountAndThemeWithoutInlineWrappers() async throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        let source = "# 제목😀\r\n**굵게** `값`\r\n"
        document.editableContent = source
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let session = EditorSession(document: document)
        document.editorSession = session
        session.mount(in: container, assetURL: Self.assetURL,
                      configuration: ["mode": "raw", "language": "markdown", "active": false])
        try await session.waitUntilReady()
        let webView = try XCTUnwrap(session.webView)
        let readRanges = """
            (() => {
                const view = window.markAgentEditorView;
                if (!window.Highlight || !CSS.highlights)
                    return [...view.dom.querySelectorAll('.hljs-section')].map(node => node.textContent);
                return [...(CSS.highlights.get('ma-tag') ?? [])].map(range => range.toString());
            })()
            """
        let mounted = try await webView.evaluateJavaScript(readRanges) as? [String]
        XCTAssertEqual(mounted, ["# 제목😀"])
        try await session.configure(["theme": ["dark": true, "tag": "#14283c"]])
        let themed = try await webView.evaluateJavaScript(readRanges) as? [String]
        XCTAssertEqual(themed, ["# 제목😀"])
        let sourceIntact = await document.withEditorSnapshot {}
        XCTAssertTrue(sourceIntact)
        XCTAssertEqual(document.editableContent, source)
        await session.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testPreviewNativeSelectAllCopyExportsSemanticHTMLAndPlainText() async throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        let source = "# 제목😀\n\n**굵게** [링크](https://example.com)\n\n- [ ] 첫째\n- [x] 둘째\n\n```swift\nlet value = 1\n```\n"
        document.content = source
        document.editableContent = source
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let session = EditorSession(document: document)
        document.editorSession = session
        session.mount(in: container, assetURL: Self.assetURL,
                      configuration: ["mode": "preview", "active": false, "showsModeToggle": true])
        try await session.waitUntilReady()
        let webView = try XCTUnwrap(session.webView)
        let codeKeyword = try await webView.evaluateJavaScript(
            "document.querySelector('pre .hljs-keyword')?.textContent"
        ) as? String
        XCTAssertEqual(codeKeyword, "let")
        let copied = expectation(description: "native Copy clipboard payload")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let probe = EditorCopyProbe { body in
            guard let body = body as? [String: String],
                  let html = body["html"], let text = body["text"] else { return }
            pasteboard.clearContents()
            pasteboard.setString(html, forType: .html)
            pasteboard.setString(text, forType: .string)
            copied.fulfill()
        }
        webView.configuration.userContentController.add(probe, name: "copyProbe")
        _ = try await webView.evaluateJavaScript("""
            window.markAgentEditorView.dom.focus();
            document.addEventListener('copy', event => {
                window.webkit.messageHandlers.copyProbe.postMessage({
                    html: event.clipboardData.getData('text/html'),
                    text: event.clipboardData.getData('text/plain')
                });
                event.clipboardData.clearData();
                event.preventDefault();
            }, {capture:true, once:true});
            """)
        let window = NSWindow(contentRect: container.bounds, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.makeFirstResponder(webView)
        defer { window.contentView = nil; window.close() }
        XCTAssertTrue(NSApp.sendAction(#selector(NSText.selectAll(_:)), to: webView, from: nil))
        XCTAssertTrue(NSApp.sendAction(#selector(NSText.copy(_:)), to: webView, from: nil))
        await fulfillment(of: [copied], timeout: 5)
        let html = try XCTUnwrap(pasteboard.string(forType: .html))
        let text = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<strong>굵게</strong>"))
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("https://example.com"))
        XCTAssertFalse(html.contains("style="))
        XCTAssertFalse(html.contains("<button"))
        XCTAssertTrue(text.contains("제목😀"))
        XCTAssertTrue(text.contains("굵게 링크"))
        XCTAssertTrue(text.contains("☐"))
        XCTAssertTrue(text.contains("☑"))
        XCTAssertFalse(text.contains("**"))
        let flushed = await document.withEditorSnapshot {}
        XCTAssertTrue(flushed)
        XCTAssertEqual(document.editableContent, source)
        XCTAssertFalse(document.isDirty)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "copyProbe")
        await session.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testPreviewResolvesDocumentRelativeImageToPortablePNGWithoutChangingSource() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.systemRed, atX: x, y: y) } }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("photo.png"))
        let document = MarkdownDocument()
        document.fileURL = directory.appendingPathComponent("document.md")
        let source = "![그림](photo.png)\n"
        document.content = source
        document.editableContent = source
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        let session = EditorSession(document: document)
        document.editorSession = session
        session.mount(in: container, assetURL: Self.assetURL, configuration: ["mode": "raw", "active": false])
        try await session.waitUntilReady()
        let webView = try XCTUnwrap(session.webView)
        let loaded = expectation(description: "document-relative PNG arrived")
        let probe = EditorCopyProbe { body in
            guard let value = body as? String else { return }
            XCTAssertTrue(value.hasPrefix("data:image/png;base64,"))
            loaded.fulfill()
        }
        webView.configuration.userContentController.add(probe, name: "imageProbe")
        _ = try await webView.evaluateJavaScript("""
            const imageObserver = new MutationObserver(() => {
                const image = document.querySelector('img[src^="data:image/png;base64,"]');
                if (!image) return;
                imageObserver.disconnect();
                window.webkit.messageHandlers.imageProbe.postMessage(image.src);
            });
            imageObserver.observe(document.body, {childList:true, subtree:true, attributes:true, attributeFilter:['src']});
            """)
        let configured = await document.withEditorSnapshot {
            try await session.configure(["mode": "preview", "active": false])
        }
        XCTAssertTrue(configured)
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertEqual(document.editableContent, source)
        XCTAssertFalse(document.isDirty)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageProbe")
        await session.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testRepresentableRemountPreservesDrainedUTF16Selection() async throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        document.editableContent = "앞😀\r\n둘😀끝\r\n"
        var retainedRange = NSRange(location: 5, length: 4)
        let binding = Binding(get: { retainedRange }, set: { retainedRange = $0 })
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }

        for cycle in 0..<3 {
            if cycle == 2 { retainedRange = NSRange(location: 100, length: 100) }
            let expected = cycle == 0 ? NSRange(location: 5, length: 4)
                : cycle == 1 ? NSRange(location: 1, length: 2)
                : NSRange(location: document.editableContent.utf16.count, length: 0)
            let appeared = expectation(description: "representable mount \(cycle)")
            let disappeared = expectation(description: "representable unmount \(cycle)")
            hosting.rootView = AnyView(
                EditorWebView(document: document, selectedRange: binding, isActive: false, assetURL: Self.assetURL)
                    .onAppear { appeared.fulfill() }
                    .onDisappear { disappeared.fulfill() }
            )
            hosting.layoutSubtreeIfNeeded()
            await fulfillment(of: [appeared], timeout: 5)
            await document.editorMount?.value
            let session = try XCTUnwrap(document.editorSession)
            try await session.waitUntilReady()
            XCTAssertEqual(session.selection, expected)
            let flushed = await document.withEditorSnapshot {}
            XCTAssertTrue(flushed)
            XCTAssertEqual(retainedRange, expected)
            let webView = try XCTUnwrap(session.webView)
            let pmRange = try await webView.evaluateJavaScript("""
                (() => {
                    const range = window.markAgentEditorView.state.selection;
                    return [range.from, range.to];
                })()
                """) as? [Int]
            XCTAssertEqual(pmRange, cycle == 0 ? [5, 9] : cycle == 1 ? [2, 4] : [10, 10])

            if cycle == 0 {
                // 마지막 선택 변경의 state 전달을 막아 drain snapshot만 부모 binding을 갱신하게 한다.
                _ = try await webView.evaluateJavaScript("""
                    (() => {
                        const handler = window.webkit.messageHandlers.markAgentEditor;
                        const post = handler.postMessage.bind(handler);
                        handler.postMessage = message => { if (message.type !== 'state') post(message); };
                        const view = window.markAgentEditorView;
                        view.dispatch(view.state.tr.setSelection(view.state.selection.constructor.create(view.state.doc, 2, 4)));
                    })()
                    """)
                XCTAssertEqual(retainedRange, expected)
            }
            hosting.rootView = AnyView(EmptyView())
            hosting.layoutSubtreeIfNeeded()
            await fulfillment(of: [disappeared], timeout: 5)
            await document.editorDrain?.value
            XCTAssertNil(document.editorSession)
            if cycle == 0 { XCTAssertEqual(retainedRange, NSRange(location: 1, length: 2)) }
        }
    }

    @MainActor
    func testNativeMenuAndCommandSSaveDelayedLatestState() async throws {
        _ = NSApplication.shared
        let suiteName = "EditorNativeSave-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tabs = TabCollection(defaults: defaults)
        let tab = tabs.createMarkdownTab(fileURL: nil)
        let document = tab.state.document
        document.editableContent = "\r\n"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        document.fileURL = directory.appendingPathComponent("save.md")
        let delegate = AppDelegate(projectStore: ProjectStore(defaults: defaults), tabs: tabs,
            subscriptionStatus: SubscriptionStatusModel(defaults: defaults, loaders: [:]))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let session = EditorSession(document: document)
        document.editorSession = session
        session.mount(in: container, assetURL: Self.assetURL, configuration: ["language": "markdown", "active": false])
        try await session.waitUntilReady()
        let webView = try XCTUnwrap(session.webView)
        let menu = NSMenu()
        let item = NSMenuItem(title: "Save", action: NSSelectorFromString("saveDocument"), keyEquivalent: "s")
        item.target = delegate
        menu.addItem(item)
        let previousMenu = NSApp.mainMenu
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = previousMenu }
        let window = MarkAgentWindow(contentRect: container.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.contentView = nil; window.close() }
        _ = try await webView.evaluateJavaScript("""
            (() => {
              const handler = window.webkit.messageHandlers.markAgentEditor;
              const post = handler.postMessage.bind(handler);
              handler.postMessage = value => { if(value.type !== 'state') post(value); };
            })()
            """)
        for (index, text) in ["메뉴😀\r\n", "키보드😀\r\n"].enumerated() {
            _ = try await webView.callAsyncJavaScript("""
                const view = window.markAgentEditorView;
                const transaction = view.state.tr.insertText(text.replaceAll('\\r\\n','\\n'), 1, view.state.doc.content.size - 1);
                view.dispatch(transaction.setSelection(view.state.selection.constructor.create(transaction.doc, 3)));
                """, arguments: ["text": text], in: nil, contentWorld: .page)
            let saved = expectation(description: "native 저장 \(index)")
            withObservationTracking { _ = document.content } onChange: { saved.fulfill() }
            if index == 0 {
                menu.performActionForItem(at: 0)
            } else {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1))
                XCTAssertTrue(window.performKeyEquivalent(with: event))
            }
            await fulfillment(of: [saved], timeout: 5)
            XCTAssertEqual(try String(contentsOf: XCTUnwrap(document.fileURL), encoding: .utf8), text)
            XCTAssertEqual(session.selection, NSRange(location: 2, length: 0))
        }
        await tab.state.stopWatching()
        await session.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testSnapshotAndThemeReconfigurationPreserveEditorFocus() async throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        document.editableContent = "한글😀"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        let session = EditorSession(document: document)
        document.editorSession = session
        session.mount(in: container, assetURL: Self.assetURL, configuration: ["language": "markdown", "active": false])
        try await session.waitUntilReady()
        let webView = try XCTUnwrap(session.webView)
        let focused = try await webView.evaluateJavaScript("""
            (() => {
              const content = window.markAgentEditorView.dom;
              content.focus();
              return document.activeElement === content;
            })()
            """) as? Bool
        XCTAssertEqual(focused, true)
        let configured = await document.withEditorSnapshot {
            try await session.configure(["language": "markdown", "theme": ["dark": true]])
        }
        XCTAssertTrue(configured)
        let retainedFocus = try await webView.evaluateJavaScript(
            "document.activeElement === window.markAgentEditorView.dom"
        ) as? Bool
        XCTAssertEqual(retainedFocus, true)
        await session.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testMountedExternalReloadAcceptAndReject() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("external.md")
        try "처음\r\n".write(to: url, atomically: true, encoding: .utf8)
        let document = MarkdownDocument()
        document.load(from: url)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        let session = EditorSession(document: document)
        document.editorSession = session
        session.mount(in: container, assetURL: Self.assetURL, configuration: ["language": "markdown", "active": false])
        try await session.waitUntilReady()
        try "clean reload\n".write(to: url, atomically: true, encoding: .utf8)
        let clean = await document.withEditorSnapshot { document.loadIfNotRecentlySaved(from: url) }
        XCTAssertTrue(clean)
        XCTAssertEqual(document.editableContent, "clean reload\n")
        XCTAssertEqual(session.epoch, 1)
        let edit = await document.withEditorSnapshot(preservingUndo: true) { document.editableContent = "내 편집😀" }
        XCTAssertTrue(edit)
        try "외부 변경\r\n".write(to: url, atomically: true, encoding: .utf8)
        let conflict = await document.withEditorSnapshot { document.loadIfNotRecentlySaved(from: url) }
        XCTAssertTrue(conflict)
        XCTAssertTrue(document.isExternalUpdatePending)
        let reject = await document.withEditorSnapshot { document.rejectExternalUpdate() }
        XCTAssertTrue(reject)
        XCTAssertEqual(document.editableContent, "내 편집😀")
        XCTAssertEqual(session.epoch, 1)
        let accept = await document.withEditorSnapshot {
            document.loadIfNotRecentlySaved(from: url)
            document.acceptExternalUpdate()
        }
        XCTAssertTrue(accept)
        XCTAssertEqual(document.editableContent, "외부 변경\r\n")
        XCTAssertEqual(session.epoch, 2)
        await session.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testFormatThemeUndoExternalResetDirtyCloseAndDrain() async throws {
        _ = NSApplication.shared
        let state = MarkdownTabState()
        let document = state.document
        let original = "😀\r\n한글\n끝\r문자\r\n"
        document.content = original
        document.editableContent = original
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        var session: EditorSession? = EditorSession(document: document)
        document.editorSession = session
        session?.mount(in: container, assetURL: Self.assetURL, configuration: ["language": "swift", "active": false])
        try await session?.waitUntilReady()
        var webView = try XCTUnwrap(session?.webView)
        let formatted = "**😀**\r\n한글\n끝\r문자\r\n"
        let applied = await document.withEditorSnapshot(preservingUndo: true) {
            document.editableContent = formatted
            session?.setHostSelection(NSRange(location: 2, length: 2))
        }
        XCTAssertTrue(applied)
        XCTAssertEqual(session?.epoch, 0)
        try await session?.configure(["language": "python", "theme": ["dark": true, "background": "#112233"]])
        XCTAssertEqual(session?.selection, NSRange(location: 2, length: 2))
        let darkScrollScheme = try await webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('#editor')).colorScheme"
        ) as? String
        XCTAssertEqual(darkScrollScheme, "dark")
        try await session?.configure(["language": "python", "theme": ["dark": false]])
        let lightScrollScheme = try await webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('#editor')).colorScheme"
        ) as? String
        XCTAssertEqual(lightScrollScheme, "light")
        _ = try await webView.evaluateJavaScript("""
            window.markAgentEditorView.dom.dispatchEvent(new KeyboardEvent('keydown',
                {key:'z',code:'KeyZ',metaKey:true,bubbles:true}))
            """)
        let undoFlushed = await document.withEditorSnapshot {}
        XCTAssertTrue(undoFlushed)
        XCTAssertEqual(document.editableContent, original)
        let external = "외부😀\r\n"
        let replaced = await document.withEditorSnapshot { document.editableContent = external }
        XCTAssertTrue(replaced)
        XCTAssertEqual(session?.epoch, 1)
        _ = try await webView.evaluateJavaScript("""
            window.markAgentEditorView.dom.dispatchEvent(new KeyboardEvent('keydown',
                {key:'z',code:'KeyZ',metaKey:true,bubbles:true}))
            """)
        let resetFlushed = await document.withEditorSnapshot {}
        XCTAssertTrue(resetFlushed)
        XCTAssertEqual(document.editableContent, external)
        document.content = external
        _ = try await webView.evaluateJavaScript("""
            (() => {
              const h=window.webkit.messageHandlers.markAgentEditor, post=h.postMessage.bind(h);
              h.postMessage=x=>{if(x.type!=='state')post(x)};
              const v=window.markAgentEditorView;
              v.dispatch(v.state.tr.insertText('지연', v.state.doc.content.size - 1));
            })()
            """)
        XCTAssertFalse(document.isDirty)
        let allowedClose = await state.prepareForClose(prompt: nil)
        XCTAssertFalse(allowedClose)
        XCTAssertTrue(document.isDirty)
        document.drainEditor()
        await document.editorDrain?.value
        XCTAssertNil(document.editorSession)
        XCTAssertEqual(document.editableContent, external + "지연")
        session = nil
        webView = WKWebView()
        let remounted = EditorSession(document: document)
        document.editorSession = remounted
        remounted.mount(in: container, assetURL: Self.assetURL, configuration: ["language": "markdown", "active": false])
        try await remounted.waitUntilReady()
        let remountFlushed = await document.withEditorSnapshot {}
        XCTAssertTrue(remountFlushed)
        XCTAssertEqual(document.editableContent, external + "지연")
        _ = try await XCTUnwrap(remounted.webView).evaluateJavaScript("""
            (() => {
              const v=window.markAgentEditorView;
              v.dom.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}));
              const bridge=window.markAgentEditor;
              window.markAgentEditor=async c=>{
                if(c.kind==='flush'){
                  const waiting=bridge(c);
                  v.dispatch(v.state.tr.insertText('한글조합', v.state.doc.content.size - 1));
                  v.dom.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'한글조합'}));
                  window.markAgentEditor=bridge;
                  await waiting;
                }else await bridge(c);
              };
            })()
            """)
        let compositionFlushed = await document.withEditorSnapshot {}
        XCTAssertTrue(compositionFlushed)
        XCTAssertEqual(document.editableContent, external + "지연한글조합")
        await remounted.dispose()
        document.editorSession = nil
    }

    @MainActor
    func testActualWebViewDelayedStateOrderedSaveSelectionAndRelease() async throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        document.editableContent = "😀\r\n한글\n"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        var session: EditorSession? = EditorSession(document: document)
        weak let releasedSession = session
        document.editorSession = session
        session?.mount(in: container, assetURL: Self.assetURL, configuration: ["language": "markdown", "active": false])
        try await session?.waitUntilReady()
        var webView = try XCTUnwrap(session?.webView)
        weak let releasedWebView: WKWebView? = webView
        let released = expectation(description: "WKWebView 해제")
        try XCTUnwrap(webView as? EditorWKWebView).onRelease = { released.fulfill() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        // 전달만 지연한다. 실제 Milkdown의 ProseMirror transaction을 적용한다.
        do {
        _ = try await webView.callAsyncJavaScript("""
            const handler = window.webkit.messageHandlers.markAgentEditor;
            const post = handler.postMessage.bind(handler);
            window.delayed = [];
            handler.postMessage = value => value.type === 'state' ? window.delayed.push(value) : post(value);
            const view = window.markAgentEditorView;
            const transaction = view.state.tr.insertText('최종😀', view.state.doc.content.size - 1);
            view.dispatch(transaction.setSelection(view.state.selection.constructor.create(transaction.doc, 3, 1)));
            window.releaseState = () => { for(const value of window.delayed) post(value); };
            """, arguments: [:], in: nil, contentWorld: .page)
        } catch {
            XCTFail("Milkdown 입력: \((error as NSError).userInfo)")
            await session?.dispose()
            throw error
        }
        XCTAssertEqual(document.editableContent, "😀\r\n한글\n")
        let saved = await document.withEditorSnapshot { try document.save(to: url) }
        XCTAssertTrue(saved, document.errorMessage ?? "")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "😀\r\n한글\n최종😀")
        XCTAssertEqual(session?.selection, NSRange(location: 0, length: 2))
        _ = try await webView.evaluateJavaScript("window.releaseState()")
        XCTAssertEqual(document.editableContent, document.content)
        let resources = try await webView.evaluateJavaScript("performance.getEntriesByType('resource').map(x=>x.name)") as? [String]
        XCTAssertTrue(try XCTUnwrap(resources).allSatisfy { $0.hasPrefix("file:") })
        await session?.dispose()
        document.editorSession = nil
        session = nil
        // 로컬 강한 참조도 해제한 뒤 weak 수명을 검사한다.
        webView = WKWebView()
        await fulfillment(of: [released], timeout: 5)
        XCTAssertNil(releasedSession)
        XCTAssertNil(releasedWebView)
    }
}

@MainActor
private final class EditorCopyProbe: NSObject, WKScriptMessageHandler {
    let receive: (Any) -> Void
    init(_ receive: @escaping (Any) -> Void) { self.receive = receive }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        receive(message.body)
    }
}
