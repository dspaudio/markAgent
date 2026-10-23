import {test, expect} from "bun:test";
import {EditorState} from "@milkdown/kit/prose/state";
import {Schema} from "@milkdown/kit/prose/model";
import {Step, Mapping, StepMap} from "@milkdown/kit/prose/transform";
import {history, undo, redo, closeHistory, undoDepth} from "@milkdown/kit/prose/history";
import {lineMap, rawPlugin, rawKey, RawStep, replacement, trackRaw, rawSelection} from "./raw-document.js";
import {rawJSON} from "./raw-schema.js";

const schema = new Schema({nodes: {doc: {content: "raw_source"},
  raw_source: {content: "text*", code: true}, text: {}}});
for (const size of [1024, 100 * 1024]) {
  test(`adjacent edits retain only changed history payload (${size} bytes)`, () => {
    const raw = "a".repeat(size), historyPlugin = history();
    let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON(raw)),
      plugins: [rawPlugin(raw), historyPlugin]});
    const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
    for (let i = 0; i < 200; i++) dispatch(state.tr.insertText("x", size / 2 + i + 1).setTime(1));
    let payload = 0, steps = 0;
    historyPlugin.getState(state).done.items.forEach(item => {
      if (!(item.step instanceof RawStep)) return;
      steps++;
      for (const value of Object.values(item.step)) if (typeof value === "string") payload += value.length;
    });
    expect(undoDepth(state)).toBe(1);
    expect(steps).toBeGreaterThan(0);
    expect(historyPlugin.getState(state).done.items.length).toBe(1);
    expect(payload).toBeLessThanOrEqual(400);
    expect(payload).toBe(200);
    expect(undo(state, dispatch)).toBe(true);
    expect(rawKey.getState(state)).toBe(raw);
    expect(redo(state, dispatch)).toBe(true);
    expect(rawKey.getState(state)).toBe(raw.slice(0, size / 2) + "x".repeat(200) + raw.slice(size / 2));
  });
}
test("혼합 줄끝과 UTF16 좌표의 앞 boundary", () => {
  const map = lineMap("😀\r\n한글\nx\ry\r\n");
  expect(map.text).toBe("😀\n한글\nx\ny\n");
  expect(map.toText(3)).toBe(2);
  expect(map.toText(4)).toBe(3);
  expect(map.toRaw(3)).toBe(4);
});
test("Enter, paste, format undo가 원문 separator를 복원한다", () => {
  const raw = "😀\r\n한글\nx\ry\r\n";
  let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON(lineMap(raw).text)),
    plugins: [rawPlugin(raw), history()]});
  const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
  dispatch(closeHistory(state.tr.insertText("\n", 3)));
  expect(rawKey.getState(state)).toBe("😀\r\n\r\n한글\nx\ry\r\n");
  expect(undo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe(raw);
  expect(redo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe("😀\r\n\r\n한글\nx\ry\r\n");
  undo(state, dispatch);
  const pasted = "😀\r\n붙임\n혼합\r\n한글\nx\ry\r\n";
  dispatch(closeHistory(replacement(state, pasted, {location: 8, length: 0})));
  expect(rawKey.getState(state)).toBe(pasted);
  expect(rawSelection(state)).toEqual({location: 8, length: 0});
  undo(state, dispatch);
  expect(rawKey.getState(state)).toBe(raw);
});
test("줄끝만 다른 호스트 replacement도 독립적으로 undo 된다", () => {
  let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON("a\nb")),
    plugins: [rawPlugin("a\r\nb"), history()]});
  const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
  dispatch(closeHistory(replacement(state, "a\nb", {location: 2, length: 1})));
  expect(rawKey.getState(state)).toBe("a\nb");
  expect(undo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe("a\r\nb");
});
test("multiple-step transactions and grouped undo preserve mixed separators", () => {
  const raw = "😀\r\n한글\nx\ry\r\n";
  let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON(lineMap(raw).text)),
    plugins: [rawPlugin(raw), history()]});
  const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
  dispatch(state.tr.insertText("A", 1).insertText("\nB", 5).setTime(1));
  dispatch(state.tr.insertText("C", 7).setTime(1));
  const edited = rawKey.getState(state);
  expect(edited).toBe("A😀\r\n\r\nBC한글\nx\ry\r\n");
  expect(undo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe(raw);
  expect(state.doc.textContent).toBe(lineMap(raw).text);
  expect(redo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe(edited);
});
test("non-history edits before a splice survive undo and redo mappings", () => {
  const raw = "😀\r\n한글\nx\ry\r\n";
  let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON(lineMap(raw).text)),
    plugins: [rawPlugin(raw), history()]});
  const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
  dispatch(replacement(state, raw.replace("한글", "**한글**"), {location: 6, length: 2}));
  dispatch(state.tr.insertText("앞\n", 1).setMeta("addToHistory", false));
  expect(undo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe("앞\r\n" + raw);
  expect(state.doc.textContent).toBe(lineMap(rawKey.getState(state)).text);
  expect(redo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe("앞\r\n" + raw.replace("한글", "**한글**"));
});
test("raw splice serialization inversion and mapping use normalized UTF16 positions", () => {
  const step = new RawStep(4, "한\r\n😀", "붙임\n");
  expect(Step.fromJSON(schema, JSON.parse(JSON.stringify(step)))).toEqual(step);
  expect(step.invert().invert()).toEqual(step);
  expect(step.invert()).toEqual(new RawStep(4, "붙임\n", "한\r\n😀"));
  const mapped = step.map(new Mapping([new StepMap([1, 0, 3])]));
  expect(mapped).toEqual(new RawStep(7, step.deleted, step.inserted));
  expect(step.map(new Mapping([new StepMap([1, 20, 0])]))).toBeNull();
});
for (const direction of ["backspace", "delete"]) {
  test(`adjacent ${direction} steps compress and preserve exact undo payload`, () => {
    const raw = "😀\r\n한글\n" + "x".repeat(200) + "\ry";
    const historyPlugin = history();
    let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON(lineMap(raw).text)),
      plugins: [rawPlugin(raw), historyPlugin]});
    const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
    for (let i = 0; i < 200; i++) {
      const from = direction === "backspace" ? 206 - i : 7;
      dispatch(state.tr.delete(from, from + 1).setTime(1));
    }
    expect(historyPlugin.getState(state).done.items.length).toBe(1);
    const step = historyPlugin.getState(state).done.items.get(0).step;
    expect(Step.fromJSON(schema, JSON.parse(JSON.stringify(step)))).toEqual(step);
    const deleted = rawKey.getState(state);
    expect(deleted).toBe("😀\r\n한글\n\ry");
    expect(undo(state, dispatch)).toBe(true);
    expect(rawKey.getState(state)).toBe(raw);
    expect(redo(state, dispatch)).toBe(true);
    expect(rawKey.getState(state)).toBe(deleted);
  });
}
test("repeated text retains the actual edit position across non-history mapping", () => {
  let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON("aaa")),
    plugins: [rawPlugin("aaa"), history()]});
  const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
  dispatch(state.tr.insertText("a", 1));
  dispatch(state.tr.insertText("X", 2).setMeta("addToHistory", false));
  expect(undo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe(state.doc.textContent);
  expect(rawKey.getState(state)).toBe("Xaaa");
  expect(redo(state, dispatch)).toBe(true);
  expect(rawKey.getState(state)).toBe(state.doc.textContent);
});
for (const [before, after] of [
  ["a\r\nb", "a\rb"], ["a\rb", "a\r\nb"], ["a\r\nb", "a\nb"],
  ["a\nb", "a\r\nb"], ["😀\r\n한\nx\ry", "😁\r\n**한**\nx\ry"]
]) {
  test(`exact raw splice round trip ${JSON.stringify([before, after])}`, () => {
    let state = EditorState.create({schema, doc: schema.nodeFromJSON(rawJSON(lineMap(before).text)),
      plugins: [rawPlugin(before), history()]});
    const dispatch = tr => { state = state.apply(trackRaw(state, tr)); };
    dispatch(replacement(state, after, {location: after.length, length: 0}));
    expect(rawKey.getState(state)).toBe(after);
    expect(rawSelection(state)).toEqual({location: after.length, length: 0});
    expect(undo(state, dispatch)).toBe(true);
    expect(rawKey.getState(state)).toBe(before);
    expect(redo(state, dispatch)).toBe(true);
    expect(rawKey.getState(state)).toBe(after);
  });
}
