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
            LazyVStack(alignment: .leading, spacing: 12) {
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
        if let checkbox = listItem.checkbox {
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SwiftUI.Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checkbox == .checked ? Color.accentColor : .secondary)
                        .imageScale(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(listItem.children.enumerated()), id: \.offset) { _, child in
                            Self.renderBlock(child)
                        }
                    }
                    .foregroundStyle(checkbox == .checked ? .secondary : .primary)
                }
            )
        }
        return AnyView(
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
            HighlightedCodeBlock(code: code, language: codeBlock.language)
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

    // MARK: Table

    mutating func visitTable(_ table: Markdown.Table) -> AnyView {
        let alignments = table.columnAlignments
        let headerCells = Array(table.head.cells)
        let bodyRows = Array(table.body.rows)

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Self.renderTableRow(
                        cells: headerCells,
                        alignments: alignments,
                        isHeader: true
                    )
                    Divider()
                    ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                        Self.renderTableRow(
                            cells: Array(row.cells),
                            alignments: alignments,
                            isHeader: false
                        )
                        Divider().opacity(0.5)
                    }
                }
            }
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

    private static func renderTableRow(
        cells: [Markdown.Table.Cell],
        alignments: [Markdown.Table.ColumnAlignment?],
        isHeader: Bool
    ) -> AnyView {
        let cellData: [(Int, Markdown.Table.Cell)] = Array(cells.enumerated()).map { ($0.offset, $0.element) }
        let columnAlignments = alignments
        return AnyView(
            HStack(spacing: 0) {
                ForEach(cellData, id: \.0) { index, cell in
                    let colAlignment: Markdown.Table.ColumnAlignment? = index < columnAlignments.count ? columnAlignments[index] : nil
                    Self.renderTableCell(cell, alignment: colAlignment, isHeader: isHeader)
                        .frame(minWidth: 80, alignment: colAlignment.swiftUIAlignment)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
        )
    }

    private static func renderTableCell(
        _ cell: Markdown.Table.Cell,
        alignment: Markdown.Table.ColumnAlignment?,
        isHeader: Bool
    ) -> some View {
        let text = renderInlineChildren(cell)
        return Group {
            if isHeader {
                text.bold()
            } else {
                text
            }
        }
        .font(.body)
        .multilineTextAlignment(alignment.textAlignment)
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

    // MARK: Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> SwiftUI.Text {
        let inner = strikethrough.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
        return inner.strikethrough()
    }
}

// MARK: - Table.ColumnAlignment Helpers

extension Optional where Wrapped == Markdown.Table.ColumnAlignment {
    var swiftUIAlignment: Alignment {
        switch self {
        case .left, .none: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .left, .none: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

// MARK: - Manual Table Rendering

private enum PreviewBlock {
    case markdown(String)
    case table(ParsedMarkdownTable)
}

private struct ParsedMarkdownTable {
    let headers: [String]
    let alignments: [Markdown.Table.ColumnAlignment?]
    let rows: [[String]]
}

private struct ManualMarkdownTableView: View {
    let table: ParsedMarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(table.headers, isHeader: true)
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                    row(cells, isHeader: false)
                    Divider().opacity(0.5)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.bottom, 8)
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { index in
                cellText(cells[safe: index] ?? "", isHeader: isHeader)
                    .font(.body)
                    .multilineTextAlignment(alignment(at: index).textAlignment)
                    .frame(minWidth: 80, alignment: alignment(at: index).swiftUIAlignment)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
    }

    private var columnCount: Int {
        max(table.headers.count, table.rows.map(\.count).max() ?? 0)
    }

    private func cellText(_ source: String, isHeader: Bool) -> SwiftUI.Text {
        let document = Document(parsing: source, options: [.parseBlockDirectives, .disableSmartOpts])
        var visitor = InlineOnlyMarkdownVisitor()
        let text = document.children.reduce(SwiftUI.Text("")) { result, child in
            result + visitor.visit(child)
        }
        return isHeader ? text.bold() : text
    }

    private func alignment(at index: Int) -> Markdown.Table.ColumnAlignment? {
        index < table.alignments.count ? table.alignments[index] : nil
    }
}

private struct InlineOnlyMarkdownVisitor: MarkupVisitor {
    typealias Result = SwiftUI.Text

    mutating func defaultVisit(_ markup: Markup) -> SwiftUI.Text {
        markup.children.reduce(SwiftUI.Text("")) { result, child in
            result + visit(child)
        }
    }

    mutating func visitText(_ text: Markdown.Text) -> SwiftUI.Text {
        SwiftUI.Text(text.string)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> SwiftUI.Text {
        defaultVisit(paragraph)
    }

    mutating func visitStrong(_ strong: Strong) -> SwiftUI.Text {
        defaultVisit(strong).bold()
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> SwiftUI.Text {
        defaultVisit(emphasis).italic()
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> SwiftUI.Text {
        SwiftUI.Text(inlineCode.code)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(Color(nsColor: .systemPink))
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> SwiftUI.Text {
        SwiftUI.Text(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> SwiftUI.Text {
        SwiftUI.Text("\n")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func parsePreviewBlocks(from source: String) -> [PreviewBlock] {
    let lines = source.components(separatedBy: .newlines)
    var blocks: [PreviewBlock] = []
    var markdownLines: [String] = []
    var index = 0
    var isInFence = false
    var fenceMarker: String?

    func flushMarkdown() {
        guard !markdownLines.isEmpty else { return }
        let markdown = markdownLines.joined(separator: "\n")
        if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.markdown(markdown))
        }
        markdownLines.removeAll()
    }

    while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if isInFence {
            if let marker = fenceMarker, trimmed.hasPrefix(marker) {
                isInFence = false
                fenceMarker = nil
            }
            markdownLines.append(line)
            index += 1
            continue
        }

        if isFenceStart(trimmed) {
            isInFence = true
            fenceMarker = String(trimmed.prefix(3))
            markdownLines.append(line)
            index += 1
            continue
        }

        if let table = parseTable(lines: lines, start: index) {
            flushMarkdown()
            blocks.append(.table(table.value))
            index = table.nextIndex
            continue
        }

        markdownLines.append(line)
        index += 1
    }

    flushMarkdown()
    return blocks
}

private func isFenceStart(_ trimmedLine: String) -> Bool {
    trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
}

private func parseTable(lines: [String], start: Int) -> (value: ParsedMarkdownTable, nextIndex: Int)? {
    guard start + 1 < lines.count else { return nil }
    guard isTableCandidate(lines[start]), isTableSeparator(lines[start + 1]) else { return nil }

    let headers = splitTableRow(lines[start])
    let alignments = splitTableRow(lines[start + 1]).map(tableAlignment)
    guard headers.count >= 2, alignments.count >= 2 else { return nil }

    var rows: [[String]] = []
    var index = start + 2
    while index < lines.count {
        let line = lines[index]
        guard isTableCandidate(line), !isTableSeparator(line) else { break }
        rows.append(splitTableRow(line))
        index += 1
    }

    return (ParsedMarkdownTable(headers: headers, alignments: alignments, rows: rows), index)
}

private func isTableCandidate(_ line: String) -> Bool {
    splitTableRow(line).count >= 2
}

private func isTableSeparator(_ line: String) -> Bool {
    let cells = splitTableRow(line)
    guard cells.count >= 2 else { return false }
    return cells.allSatisfy { cell in
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
    }
}

private func splitTableRow(_ line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") { trimmed.removeFirst() }
    if trimmed.hasSuffix("|") { trimmed.removeLast() }

    var cells: [String] = []
    var current = ""
    var isEscaped = false

    for character in trimmed {
        if isEscaped {
            current.append(character)
            isEscaped = false
        } else if character == "\\" {
            isEscaped = true
        } else if character == "|" {
            cells.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
        } else {
            current.append(character)
        }
    }

    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
}

private func tableAlignment(_ source: String) -> Markdown.Table.ColumnAlignment? {
    let trimmed = source.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") {
        return .center
    }
    if trimmed.hasSuffix(":") {
        return .right
    }
    return .left
}

// MARK: - Public API

@MainActor
func renderMarkdown(_ source: String) -> AnyView {
    let blocks = parsePreviewBlocks(from: source)
    if blocks.count == 1, case .markdown(let markdown) = blocks[0] {
        return renderMarkdownDocument(markdown)
    }

    return AnyView(
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let markdown):
                    renderMarkdownDocument(markdown)
                case .table(let table):
                    ManualMarkdownTableView(table: table)
                }
            }
        }
    )
}

@MainActor
private func renderMarkdownDocument(_ source: String) -> AnyView {
    let document = Document(parsing: source, options: [.parseBlockDirectives, .disableSmartOpts])
    var renderer = MarkdownRenderer()
    return renderer.visit(document)
}
