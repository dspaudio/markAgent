import Markdown
import SwiftUI

// MARK: - MarkdownRenderer

struct MarkdownRenderer: MarkupVisitor {
    typealias Result = AnyView

    // MARK: Default

    mutating func defaultVisit(_ markup: Markup) -> AnyView {
        let children = Array(markup.children)
        if children.isEmpty {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    Self.renderBlock(child)
                }
            }
        )
    }

    // MARK: Document

    mutating func visitDocument(_ document: Document) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                    Self.renderBlock(child)
                }
            }
        )
    }

    // MARK: Heading

    mutating func visitHeading(_ heading: Heading) -> AnyView {
        let text = Self.renderInlineChildren(heading)
        let font = Self.headingFont(level: heading.level)
        let topPadding: CGFloat = heading.level <= 2 ? 16 : 8
        let bottomPadding: CGFloat = heading.level <= 2 ? 8 : 4

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                text.font(font)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                if heading.level <= 2 {
                    Divider()
                }
            }
        )
    }

    // MARK: Paragraph

    mutating func visitParagraph(_ paragraph: Paragraph) -> AnyView {
        let text = Self.renderInlineChildren(paragraph)
        return AnyView(
            text
                .font(.body)
                .padding(.bottom, 8)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    // MARK: BlockQuote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                        Self.renderBlock(child)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        )
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(unorderedList.children.enumerated()), id: \.offset) { _, child in
                    Self.renderBlock(child)
                }
            }
            .padding(.bottom, 8)
        )
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> AnyView {
        let items = Array(orderedList.children)
        let startIndex = orderedList.startIndex
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, child in
                    Self.renderOrderedListItem(child, number: startIndex + UInt(index))
                }
            }
            .padding(.bottom, 8)
        )
    }

    mutating func visitListItem(_ listItem: ListItem) -> AnyView {
        AnyView(
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SwiftUI.Text("•")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(listItem.children.enumerated()), id: \.offset) { _, child in
                        Self.renderBlock(child)
                    }
                }
            }
        )
    }

    // MARK: CodeBlock

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> AnyView {
        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                SwiftUI.Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 8)
        )
    }

    // MARK: ThematicBreak

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> AnyView {
        AnyView(
            Divider()
                .padding(.vertical, 12)
        )
    }

    // MARK: HTMLBlock

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> AnyView {
        AnyView(
            SwiftUI.Text(html.rawHTML)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        )
    }

    // MARK: Static Helpers

    static func renderInlineChildren(_ node: some Markup) -> SwiftUI.Text {
        var visitor = InlineTextVisitor()
        return node.children.reduce(SwiftUI.Text("")) { result, child in
            result + visitor.visit(child)
        }
    }

    static func renderBlock(_ node: Markup) -> AnyView {
        var renderer = MarkdownRenderer()
        return renderer.visit(node)
    }

    private static func renderOrderedListItem(_ node: Markup, number: UInt) -> AnyView {
        AnyView(
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SwiftUI.Text("\(number).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        Self.renderBlock(child)
                    }
                }
            }
        )
    }

    private static func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle.bold()
        case 2: return .title.bold()
        case 3: return .title2.bold()
        case 4: return .title3.bold()
        case 5: return .headline
        case 6: return .subheadline.bold()
        default: return .body
        }
    }
}

// MARK: - InlineTextVisitor

struct InlineTextVisitor: MarkupVisitor {
    typealias Result = SwiftUI.Text

    mutating func defaultVisit(_ markup: Markup) -> SwiftUI.Text {
        markup.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
    }

    // MARK: Text

    mutating func visitText(_ text: Markdown.Text) -> SwiftUI.Text {
        SwiftUI.Text(text.string)
    }

    // MARK: Strong

    mutating func visitStrong(_ strong: Strong) -> SwiftUI.Text {
        let inner = strong.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
        return inner.bold()
    }

    // MARK: Emphasis

    mutating func visitEmphasis(_ emphasis: Emphasis) -> SwiftUI.Text {
        let inner = emphasis.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
        return inner.italic()
    }

    // MARK: InlineCode

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> SwiftUI.Text {
        SwiftUI.Text(inlineCode.code)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(Color(nsColor: .systemPink))
    }

    // MARK: Link

    mutating func visitLink(_ link: Markdown.Link) -> SwiftUI.Text {
        let inner = link.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
        return inner.foregroundColor(.blue).underline()
    }

    // MARK: Image

    mutating func visitImage(_ image: Markdown.Image) -> SwiftUI.Text {
        let altText = image.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
        return SwiftUI.Text("[image] ") + altText
    }

    // MARK: SoftBreak / LineBreak

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> SwiftUI.Text {
        SwiftUI.Text(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> SwiftUI.Text {
        SwiftUI.Text("\n")
    }

    // MARK: InlineHTML

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> SwiftUI.Text {
        SwiftUI.Text(inlineHTML.rawHTML)
            .foregroundColor(.secondary)
    }
}

// MARK: - Public API

func renderMarkdown(_ source: String) -> AnyView {
    let document = Document(parsing: source, options: [.parseBlockDirectives])
    var renderer = MarkdownRenderer()
    return renderer.visit(document)
}
