import {test, expect, afterEach} from "bun:test";
import {Window} from "happy-dom";
const dom = new Window();
for (const key of ["window", "document", "navigator", "Node", "HTMLElement", "Element",
  "MutationObserver", "DOMParser", "getComputedStyle", "requestAnimationFrame", "cancelAnimationFrame"]) {
  globalThis[key] = key === "window" ? dom : typeof dom[key] === "function" && /^(getComputed|request|cancel)/.test(key)
    ? dom[key].bind(dom) : dom[key];
}
const {Editor, rootCtx, defaultValueCtx, editorViewCtx} = await import("@milkdown/kit/core");
const {rawSchema, rawJSON} = await import("./raw-schema.js");

test("실제 Milkdown 원문 스키마는 fence 없이 원문을 그대로 보유한다", async () => {
  const root = document.createElement("div");
  document.body.append(root);
  const source = "# 제목\r\n😀\n끝\r문자\n```\n";
  const editor = await Editor.make().config(ctx => {
    ctx.set(rootCtx, root);
    ctx.set(defaultValueCtx, {type: "json", value: rawJSON(source)});
  }).use(rawSchema).create();
  const view = editor.ctx.get(editorViewCtx);
  expect(view.state.doc.firstChild.type.name).toBe("raw_source");
  expect(view.state.doc.textContent).toBe(source);
  expect(root.querySelector(".ProseMirror")).not.toBeNull();
  expect(root.querySelector(".cm-editor")).toBeNull();
  await editor.destroy();
  root.remove();
});

document.body.innerHTML = '<button id="mode-toggle"></button><main id="editor"></main>';
const messages = [];
window.webkit = {messageHandlers: {markAgentEditor: {postMessage: message => messages.push(message)}}};
await import("./entry.js");
const {undo, redo} = await import("@milkdown/kit/prose/history");
const {neutralCopy} = await import("./neutral-copy.js");
let live = false, epoch = 0;
const command = data => window.markAgentEditor({version: 1, sessionID: "runtime", epoch, ...data});
const view = () => window.markAgentEditorView;
async function initialize(text, extra = {}) {
  messages.length = 0; epoch = 0;
  await command({kind: "initialize", text, selection: {location: 0, length: 0},
    mode: "raw", active: false, showsModeToggle: true, ...extra});
  live = true;
}
async function flush() {
  await command({kind: "flush", requestID: "flush"});
  return messages.at(-1);
}
afterEach(async () => {
  if (live) { await command({kind: "dispose"}); live = false; }
});
test("원문 latest snapshot, UTF16 선택, undo/redo와 host reset", async () => {
  const raw = "# 제목😀\r\n끝\r문자\n";
  await initialize(raw);
  const v = view();
  expect(v.state.doc.firstChild.type.name).toBe("raw_source");
  expect(document.activeElement).not.toBe(v.dom);
  v.dispatch(v.state.tr.insertText("추가😀", v.state.doc.content.size - 1));
  expect((await flush()).text).toBe(raw + "추가😀");
  v.dispatch(v.state.tr.insertText("잠김", 1));
  expect((await flush()).text).toBe(raw + "추가😀");
  await command({kind: "apply", operation: "format", text: "**포맷😀**\r\n", selection: {location: 2, length: 4}, requestID: "format"});
  await command({kind: "resume"});
  expect((await flush()).selection).toEqual({location: 2, length: 4});
  await command({kind: "resume"});
  expect(undo(v.state, v.dispatch)).toBe(true);
  expect((await flush()).text).toBe(raw + "추가😀");
  await command({kind: "resume"});
  expect(redo(v.state, v.dispatch)).toBe(true);
  expect((await flush()).text).toBe("**포맷😀**\r\n");
  epoch++;
  await command({kind: "apply", operation: "replace", text: "외부\r\n", selection: {location: 0, length: 0}, requestID: "replace"});
  await command({kind: "resume"});
  expect(undo(view().state, view().dispatch)).toBe(false);
  expect((await flush()).text).toBe("외부\r\n");
  expect(messages.every((m, i) => m.version === 1 && m.sessionID === "runtime" && m.seq === i + 1)).toBe(true);
});
test("IME compositionend 신호 뒤 DOM의 마지막 입력을 flush 한다", async () => {
  await initialize("처음\r\n");
  const v = view();
  v.dom.dispatchEvent(new dom.CompositionEvent("compositionstart", {bubbles: true}));
  const pending = flush();
  expect(messages.at(-1).type).not.toBe("snapshot");
  v.dom.querySelector("pre").firstChild.textContent = "한글😀\n";
  v.dom.dispatchEvent(new dom.CompositionEvent("compositionend", {bubbles: true, data: "한글😀"}));
  expect((await pending).text).toBe("한글😀\r\n");
});
test("Preview는 읽기 전용 GFM이며 DOM 복사는 문법과 테마를 제외한다", async () => {
  const source = "# 제목\n\n**굵게** [링크](https://example.com)\n\n- 하나\n- 둘\n- [ ] 미완료\n- [x] 완료\n\n| A | B |\n| - | - |\n| 값 | 둘 |\n\n```js\nlet x = 1;\n```\n\n![그림](data:image/png;base64,AA==)\n";
  await initialize(source, {mode: "preview"});
  const v = view();
  expect(v.editable).toBe(false);
  for (const selector of ["h1", "strong", "a", "ul li", "table td", "pre code", "img"]) expect(v.dom.querySelector(selector)).not.toBeNull();
  expect(v.dom.querySelector("pre .hljs-keyword")?.textContent).toBe("let");
  expect(v.dom.querySelector("pre .hljs-number")?.textContent).toBe("1");
  v.dispatch(v.state.tr.insertText("변조", 1));
  const selection = window.getSelection(), range = document.createRange();
  range.selectNodeContents(v.dom); selection.removeAllRanges(); selection.addRange(range);
  const copied = neutralCopy(v.dom);
  expect(copied.html).toContain("<strong>굵게</strong>");
  expect(copied.html).toContain("<table>");
  expect(copied.html).not.toMatch(/class=|style=|data-|contenteditable/);
  expect(copied.text).toContain("굵게 링크");
  expect(copied.text).toContain("☐ 미완료");
  expect(copied.text).toContain("☑ 완료");
  expect(copied.html).toContain("☐ ");
  expect(copied.html).toContain("☑ ");
  expect(copied.text).not.toContain("**");
  expect(copied.text).not.toContain("```");
  const strong = v.dom.querySelector("strong").firstChild;
  range.setStart(strong, 0); range.setEnd(strong, 1);
  selection.removeAllRanges(); selection.addRange(range);
  expect(neutralCopy(v.dom).html).toContain("<strong>굵</strong>");
  expect((await flush()).text).toBe(source);
});
test("모드 왕복은 raw undo와 source를 유지하고 버튼은 완전한 envelope를 전송한다", async () => {
  await initialize("원문\r\n");
  view().dispatch(view().state.tr.insertText("입력", 1));
  await flush();
  await command({kind: "apply", operation: "configure", mode: "preview", requestID: "preview"});
  await command({kind: "resume"});
  expect(view().editable).toBe(false);
  expect((await flush()).text).toBe("입력원문\r\n");
  document.getElementById("mode-toggle").click();
  expect(messages.at(-1)).toMatchObject({type: "modeToggle", version: 1, sessionID: "runtime", epoch: 0});
  await command({kind: "apply", operation: "configure", mode: "raw", showsModeToggle: false, requestID: "raw"});
  await command({kind: "resume"});
  expect(document.getElementById("mode-toggle").hidden).toBe(true);
  expect(undo(view().state, view().dispatch)).toBe(true);
  expect((await flush()).text).toBe("원문\r\n");
  await command({kind: "dispose"}); live = false;
  expect(document.querySelector(".ProseMirror")).toBeNull();
  await expect(command({kind: "resume"})).rejects.toThrow("session");
});

test("raw paste/copy/cut는 혼합 원문을 그대로 전달한다", async () => {
  await initialize("😀\r\n끝");
  const v = view();
  const clipboard = new dom.DataTransfer();
  clipboard.setData("text/plain", "**원문**\r\n혼합\n");
  v.dom.dispatchEvent(new dom.ClipboardEvent("paste", {bubbles: true, cancelable: true, clipboardData: clipboard}));
  const expected = "**원문**\r\n혼합\n😀\r\n끝";
  expect((await flush()).text).toBe(expected);
  await command({kind: "apply", operation: "format", text: expected, selection: {location: 0, length: 11}, requestID: "selection"});
  await command({kind: "resume"});
  const copied = new dom.DataTransfer();
  v.dom.dispatchEvent(new dom.ClipboardEvent("copy", {bubbles: true, cancelable: true, clipboardData: copied}));
  expect(copied.getData("text/plain")).toBe(expected.slice(0, 11));
  expect(copied.getData("text/html")).toBe("");
  v.dom.dispatchEvent(new dom.ClipboardEvent("cut", {bubbles: true, cancelable: true, clipboardData: copied}));
  expect((await flush()).text).toBe(expected.slice(11));
});

test("preview Cmd+A와 Copy는 의미 HTML 및 일반 텍스트를 함께 제공한다", async () => {
  await initialize("문단 **굵게**\n\n- 첫째\n- 둘째\n", {mode: "preview"});
  const v = view();
  v.dom.dispatchEvent(new dom.KeyboardEvent("keydown", {key: "a", metaKey: true, bubbles: true, cancelable: true}));
  const clipboard = new dom.DataTransfer();
  v.dom.dispatchEvent(new dom.ClipboardEvent("copy", {bubbles: true, cancelable: true, clipboardData: clipboard}));
  expect(clipboard.getData("text/html")).toContain("<strong>굵게</strong>");
  expect(clipboard.getData("text/html")).toContain("<ul>");
  expect(clipboard.getData("text/plain")).toContain("문단 굵게\n");
  expect(clipboard.getData("text/plain")).not.toContain("**");
});

test("theme 구성과 저장 장벽은 focus를 빼앗지 않으며 명시적 inactive는 해제한다", async () => {
  await initialize("내용");
  const v = view();
  v.focus();
  expect(v.hasFocus()).toBe(true);
  await flush();
  await command({kind: "apply", operation: "configure", theme: {dark: true}, requestID: "theme"});
  await command({kind: "resume"});
  expect(v.hasFocus()).toBe(true);
  await command({kind: "apply", operation: "configure", active: false, requestID: "inactive"});
  expect(v.hasFocus()).toBe(false);
  await flush();
  await command({kind: "apply", operation: "configure", active: true, requestID: "active"});
  expect(view()).toBe(v);
  expect(v.hasFocus()).toBe(false);
  await command({kind: "resume"});
  expect(v.hasFocus()).toBe(true);
  v.dom.blur();
  await command({kind: "apply", operation: "configure", theme: {dark: false}, requestID: "blurred-theme"});
  expect(v.hasFocus()).toBe(false);
});

test("Native 전체 선택은 body를 포함해도 Preview 문서만 복사한다", async () => {
  await initialize("# 제목\n\n**본문**\n", {mode: "preview"});
  const selection = window.getSelection(), range = document.createRange();
  range.selectNodeContents(document.body);
  selection.removeAllRanges(); selection.addRange(range);
  const clipboard = new dom.DataTransfer();
  document.body.dispatchEvent(new dom.ClipboardEvent("copy", {bubbles: true, cancelable: true, clipboardData: clipboard}));
  expect(clipboard.getData("text/html")).toContain("<h1>제목</h1>");
  expect(clipboard.getData("text/html")).not.toContain("<button");
  expect(clipboard.getData("text/plain")).toBe("제목\n본문");
});

test("Preview 이미지 응답은 원문을 바꾸지 않고 portable data URI를 표시한다", async () => {
  const source = "![그림](../photo.png)\n\n[문서](next.md)\n";
  await initialize(source, {mode: "preview", baseURL: "file:///tmp/docs/"});
  const imageRequest = messages.find(message => message.type === "image");
  expect(imageRequest.source).toBe("../photo.png");
  const png = "data:image/png;base64,AA==";
  await command({kind: "image", imageID: imageRequest.imageID, src: png, url: "file:///tmp/photo.png"});
  expect(view().dom.querySelector(`img[src="${png}"]`).src).toBe(png);
  expect(view().dom.querySelector("a").href).toBe("file:///tmp/docs/next.md");
  const selection = window.getSelection(), range = document.createRange();
  range.selectNodeContents(view().dom); selection.removeAllRanges(); selection.addRange(range);
  expect(neutralCopy(view().dom).html).toContain(png);
  expect((await flush()).text).toBe(source);
});

test("원문 문법 색상은 편집 DOM을 감싸지 않고 범위만 갱신하고 해제한다", async () => {
  const registry = new Map();
  const browser = document.defaultView;
  const previousCSS = Object.getOwnPropertyDescriptor(browser, "CSS"), previousHighlight = browser.Highlight;
  Object.defineProperty(browser, "CSS", {configurable: true, value: {...browser.CSS, highlights: registry}});
  browser.Highlight = class extends Set {};
  registry.set("foreign", new Set());
  try {
    const raw = "# 제목😀\r\n**굵게** `값`\r\n";
    await initialize(raw);
    const v = view();
    expect(v.dom.querySelectorAll("pre code, .raw-syntax").length).toBe(0);
    expect([...v.dom.querySelector("pre").childNodes].filter(node => node.nodeType === 3).length).toBe(1);
    expect([...registry.get("ma-tag")].map(range => range.toString())).toContain("# 제목😀");
    v.dispatch(v.state.tr.insertText("앞", 3));
    expect([...registry.get("ma-tag")].map(range => range.toString())).toContain("# 앞제목😀");
    expect((await flush()).text).toBe(raw.replace("# 제목", "# 앞제목"));
    await command({kind: "dispose"});
    live = false;
    expect([...registry.keys()]).toEqual(["foreign"]);
  } finally {
    if (live) { await command({kind: "dispose"}); live = false; }
    Object.defineProperty(browser, "CSS", previousCSS);
    browser.Highlight = previousHighlight;
  }
});
