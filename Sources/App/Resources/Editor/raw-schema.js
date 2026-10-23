import {$node} from "@milkdown/kit/utils";

// 원문은 Markdown 파서/serializer를 절대로 거치지 않는다.
const unused = {match: () => false, runner: () => { throw new Error("원문 Markdown 변환 금지"); }};
export const rawSchema = [
  $node("doc", () => ({content: "raw_source", parseMarkdown: unused, toMarkdown: unused})),
  $node("raw_source", () => ({
    content: "text*", marks: "", code: true, defining: true,
    parseDOM: [{tag: "pre", preserveWhitespace: "full"}],
    toDOM: () => ["pre", 0],
    parseMarkdown: unused, toMarkdown: unused
  })),
  $node("text", () => ({group: "inline", parseMarkdown: unused, toMarkdown: unused}))
];
export function rawJSON(text) {
  return {type: "doc", content: [{type: "raw_source",
    content: text ? [{type: "text", text}] : []}]};
}
