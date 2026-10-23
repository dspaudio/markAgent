import {Plugin, PluginKey, TextSelection} from "@milkdown/kit/prose/state";
import {Step, StepResult} from "@milkdown/kit/prose/transform";

// PM 좌표는 단일 code 노드 안의 LF UTF-16 + 1, wire는 원문 UTF-16이다.
export function lineMap(raw) {
  const rawStarts = [0], textStarts = [0], separators = [];
  let text = "", start = 0;
  for (const match of raw.matchAll(/\r\n|\r|\n/g)) {
    text += raw.slice(start, match.index) + "\n";
    separators.push(match[0]);
    start = match.index + match[0].length;
    rawStarts.push(start);
    textStarts.push(text.length);
  }
  text += raw.slice(start);
  function lineAt(starts, offset) {
    let lo = 0, hi = starts.length;
    while (lo + 1 < hi) {
      const mid = (lo + hi) >> 1;
      if (starts[mid] <= offset) lo = mid; else hi = mid;
    }
    return lo;
  }
  return {text, separators,
    toRaw(offset) {
      offset = Math.max(0, Math.min(text.length, offset));
      const line = lineAt(textStarts, offset);
      return rawStarts[line] + offset - textStarts[line];
    },
    toText(offset) {
      offset = Math.max(0, Math.min(raw.length, offset));
      const line = lineAt(rawStarts, offset);
      const end = line + 1 < textStarts.length ? textStarts[line + 1] - 1 : text.length;
      return Math.min(end, textStarts[line] + offset - rawStarts[line]);
    }
  };
}

// 줄끝 metadata도 PM history의 같은 transaction에서 역전된다.
export class RawStep extends Step {
  // from은 PM UTF-16 좌표이며 payload에 변경된 원문만 보관한다.
  constructor(from, deleted, inserted, step = null) {
    super(); this.from = from; this.deleted = deleted; this.inserted = inserted; this.step = step;
  }
  apply(doc) { return this.step ? this.step.apply(doc) : StepResult.ok(doc); }
  getMap() { return this.step ? this.step.getMap() : super.getMap(); }
  invert(doc) { return new RawStep(this.from, this.inserted, this.deleted, this.step?.invert(doc)); }
  map(mapping) {
    const step = this.step?.map(mapping);
    if (this.step && !step) return null;
    const from = mapping.mapResult(this.from, 1);
    const to = mapping.mapResult(this.from + lineMap(this.deleted).text.length, -1);
    if (from.deletedAcross && to.deletedAcross) return null;
    return new RawStep(from.pos, this.deleted, this.inserted, step);
  }
  merge(other) {
    if (!(other instanceof RawStep) || !this.step || !other.step) return null;
    const step = this.step.merge(other.step);
    if (!step) return null;
    if (!this.deleted && !other.deleted) {
      if (other.from === this.from + lineMap(this.inserted).text.length)
        return new RawStep(this.from, "", this.inserted + other.inserted, step);
      if (other.from === this.from)
        return new RawStep(this.from, "", other.inserted + this.inserted, step);
    }
    if (!this.inserted && !other.inserted) {
      if (other.from === this.from)
        return new RawStep(this.from, this.deleted + other.deleted, "", step);
      if (other.from + lineMap(other.deleted).text.length === this.from)
        return new RawStep(other.from, other.deleted + this.deleted, "", step);
    }
    return null;
  }
  toJSON() {
    return {stepType: "markAgentRaw", from: this.from, deleted: this.deleted, inserted: this.inserted,
      step: this.step?.toJSON() ?? null};
  }
  static fromJSON(schema, value) {
    return new RawStep(value.from, value.deleted, value.inserted, value.step ? Step.fromJSON(schema, value.step) : null);
  }
  static between(before, after, step = null) {
    let from = 0, endBefore = before.length, endAfter = after.length;
    while (from < endBefore && from < endAfter && before[from] === after[from]) from++;
    while (endBefore > from && endAfter > from && before[endBefore - 1] === after[endAfter - 1]) {
      endBefore--; endAfter--;
    }
    // CRLF 중간은 PM 좌표로 표현할 수 없으므로 separator 전체를 포함한다.
    if (before[from - 1] === "\r" && (before[from] === "\n" || after[from] === "\n")) from--;
    if (before[endBefore - 1] === "\r" && before[endBefore] === "\n"
        || after[endAfter - 1] === "\r" && after[endAfter] === "\n") {
      endBefore++; endAfter++;
    }
    return new RawStep(lineMap(before).toText(from) + 1, before.slice(from, endBefore), after.slice(from, endAfter), step);
  }
}
Step.jsonID("markAgentRaw", RawStep);
export const rawKey = new PluginKey("markAgentRaw");
export function rawPlugin(raw) {
  return new Plugin({key: rawKey, state: {
    init: () => raw,
    apply: (tr, value) => {
      for (const step of tr.steps) {
        if (!(step instanceof RawStep)) continue;
        const from = lineMap(value).toRaw(step.from - 1);
        value = value.slice(0, from) + step.inserted + value.slice(from + step.deleted.length);
      }
      return value;
    }
  }});
}
export function trackRaw(state, tr) {
  if (!tr.docChanged || tr.steps.some(step => step instanceof RawStep)) return tr;
  let raw = rawKey.getState(state);
  tr.steps.forEach((step, index) => {
    const before = raw;
    const map = lineMap(raw), afterDoc = tr.docs[index + 1] ?? tr.doc;
    let next = "", cursor = 0, start = null;
    step.getMap().forEach((from, to, newFrom, newTo) => {
      const rawFrom = map.toRaw(from - 1), rawTo = map.toRaw(to - 1);
      start ??= rawFrom;
      const inserted = afterDoc.textBetween(newFrom, newTo, "").replace(/\n/g, map.separators[0] ?? "\n");
      next += raw.slice(cursor, rawFrom) + inserted;
      cursor = rawTo;
    });
    raw = next + raw.slice(cursor);
    // 이미 계산된 docs/maps는 그대로 두고 동등한 PM step과 원문 splice를 함께 보관한다.
    tr.steps[index] = start === null ? RawStep.between(before, raw, step)
      : new RawStep(map.toText(start) + 1, before.slice(start, cursor),
        raw.slice(start, raw.length - (before.length - cursor)), step);
  });
  return tr;
}
export function rawSelection(state) {
  const map = lineMap(rawKey.getState(state));
  const start = map.toRaw(state.selection.from - 1), end = map.toRaw(state.selection.to - 1);
  return {location: start, length: end - start};
}
export function selectionFor(doc, raw, selection) {
  const map = lineMap(raw);
  return TextSelection.create(doc, map.toText(selection.location) + 1,
    map.toText(selection.location + selection.length) + 1);
}
export function replacement(state, raw, selection) {
  const before = state.doc.textContent, after = lineMap(raw).text;
  let from = 0, endBefore = before.length, endAfter = after.length;
  while (from < endBefore && from < endAfter && before[from] === after[from]) from++;
  while (endBefore > from && endAfter > from && before[endBefore - 1] === after[endAfter - 1]) {
    endBefore--; endAfter--;
  }
  const tr = state.tr;
  if (from !== endBefore || from !== endAfter) tr.insertText(after.slice(from, endAfter), from + 1, endBefore + 1);
  const step = RawStep.between(rawKey.getState(state), raw, tr.steps[0]);
  if (tr.steps.length) tr.steps[0] = step; else tr.step(step);
  return tr.setSelection(selectionFor(tr.doc, raw, selection));
}
