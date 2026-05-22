import SwiftUI

struct DiffOverlayView: View {
    let diffResult: DiffResult
    var baseURL: URL?
    let onClose: () -> Void

    @State private var expandedTopCounts: [Int: Int] = [:]
    @State private var expandedBottomCounts: [Int: Int] = [:]

    private let collapsedContextThreshold = 6
    private let expansionStep = 20
    private let visibleContextLines = 3

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            diffList
        }
        .onAppear(perform: resetExpandedState)
        .onChange(of: diffSignature) { _, _ in
            resetExpandedState()
        }
    }

    // MARK: - 하위 뷰

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .foregroundStyle(.secondary)

            Text(summaryText)
                .font(.callout.weight(.medium))

            Spacer()

            Button("Diff 닫기") {
                onClose()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var diffList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sections) { section in
                    switch section {
                    case .rows(let id, let rows):
                        ForEach(rows) { row in
                            switch row.kind {
                            case .line(let line):
                                DiffHighlighter(line: line, baseURL: baseURL)
                                    .id("line-\(id)-\(row.id)")
                            case .imagePair(let before, let after):
                                ImageDiffPairView(before: before, after: after)
                                    .id("image-\(id)-\(row.id)")
                            }
                            Divider().opacity(0.3)
                        }
                    case .collapsed(let context):
                        collapsedContextView(context)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 헬퍼

    private var summaryText: String {
        var parts: [String] = []
        if diffResult.addedCount > 0 {
            parts.append("+\(diffResult.addedCount)줄")
        }
        if diffResult.removedCount > 0 {
            parts.append("-\(diffResult.removedCount)줄")
        }
        return parts.isEmpty ? "변경 없음" : parts.joined(separator: ", ")
    }

    private var sections: [DiffSection] {
        buildSections(from: diffResult.lines)
    }

    private var diffSignature: String {
        diffResult.lines.map {
            "\($0.type.signature):\($0.oldLineNumber ?? -1):\($0.lineNumber ?? -1):\($0.content)"
        }.joined(separator: "\u{1f}")
    }

    private func resetExpandedState() {
        expandedTopCounts = [:]
        expandedBottomCounts = [:]
    }

    private func buildSections(from lines: [DiffLine]) -> [DiffSection] {
        var builtSections: [DiffSection] = []
        var hunkBuffer: [DiffLine] = []
        var index = 0
        var sectionID = 0

        while index < lines.count {
            let line = lines[index]

            if line.type != .unchanged {
                hunkBuffer.append(line)
                index += 1
                continue
            }

            var unchangedBuffer: [DiffLine] = []
            while index < lines.count, lines[index].type == .unchanged {
                unchangedBuffer.append(lines[index])
                index += 1
            }

            let hasChangeBefore = !hunkBuffer.isEmpty
            let hasChangeAfter = lines[index...].contains { $0.type != .unchanged }

            if unchangedBuffer.count <= collapsedContextThreshold || (!hasChangeBefore && !hasChangeAfter) {
                hunkBuffer.append(contentsOf: unchangedBuffer)
                continue
            }

            let preservedTopCount = hasChangeBefore ? min(visibleContextLines, unchangedBuffer.count) : 0
            let preservedBottomCount = hasChangeAfter ? min(visibleContextLines, unchangedBuffer.count - preservedTopCount) : 0
            let hiddenStart = preservedTopCount
            let hiddenEnd = unchangedBuffer.count - preservedBottomCount
            let hiddenLines = hiddenStart < hiddenEnd ? Array(unchangedBuffer[hiddenStart..<hiddenEnd]) : []

            if preservedTopCount > 0 {
                hunkBuffer.append(contentsOf: unchangedBuffer.prefix(preservedTopCount))
            }

            if !hunkBuffer.isEmpty {
                builtSections.append(.rows(id: sectionID, rows: makeRows(from: hunkBuffer, prefix: "section-\(sectionID)")))
                sectionID += 1
                hunkBuffer.removeAll(keepingCapacity: true)
            }

            if !hiddenLines.isEmpty {
                builtSections.append(
                    .collapsed(
                        .init(
                            id: sectionID,
                            hiddenLines: hiddenLines,
                            canExpandTop: hasChangeBefore,
                            canExpandBottom: hasChangeAfter
                        )
                    )
                )
                sectionID += 1
            }

            if preservedBottomCount > 0 {
                hunkBuffer.append(contentsOf: unchangedBuffer.suffix(preservedBottomCount))
            }
        }

        if !hunkBuffer.isEmpty {
            builtSections.append(.rows(id: sectionID, rows: makeRows(from: hunkBuffer, prefix: "section-\(sectionID)")))
        }

        return builtSections
    }

    private func makeRows(from lines: [DiffLine], prefix: String) -> [DiffRenderableRow] {
        var rows: [DiffRenderableRow] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.type == .removed,
               index + 1 < lines.count,
               lines[index + 1].type == .added,
               let before = MarkdownImageLineParser.firstImage(in: line.content, baseURL: baseURL),
               let after = MarkdownImageLineParser.firstImage(in: lines[index + 1].content, baseURL: baseURL) {
                rows.append(.init(id: "\(prefix)-\(index)", kind: .imagePair(before: before, after: after)))
                index += 2
            } else {
                rows.append(.init(id: "\(prefix)-\(index)", kind: .line(line)))
                index += 1
            }
        }
        return rows
    }

    @ViewBuilder
    private func collapsedContextView(_ context: CollapsedContextSection) -> some View {
        let topCount = expandedTopCounts[context.id] ?? 0
        let bottomCount = expandedBottomCounts[context.id] ?? 0
        let remainingCount = max(context.hiddenLines.count - topCount - bottomCount, 0)
        let topLines = Array(context.hiddenLines.prefix(topCount))
        let bottomLines = Array(context.hiddenLines.suffix(bottomCount))

        ForEach(makeRows(from: topLines, prefix: "collapsed-top-\(context.id)")) { row in
            switch row.kind {
            case .line(let line):
                DiffHighlighter(line: line, baseURL: baseURL)
            case .imagePair(let before, let after):
                ImageDiffPairView(before: before, after: after)
            }
            Divider().opacity(0.3)
        }

        if remainingCount > 0 {
            HStack(spacing: 12) {
                if context.canExpandTop {
                    Button {
                        expandedTopCounts[context.id] = min(topCount + expansionStep, context.hiddenLines.count - bottomCount)
                    } label: {
                        Label("\(min(expansionStep, remainingCount))줄 더 보기", systemImage: "chevron.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer(minLength: 0)

                Text("\(remainingCount)줄 숨김")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if context.canExpandBottom {
                    Button {
                        expandedBottomCounts[context.id] = min(bottomCount + expansionStep, context.hiddenLines.count - topCount)
                    } label: {
                        Label("\(min(expansionStep, remainingCount))줄 더 보기", systemImage: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))

            Divider().opacity(0.3)
        }

        ForEach(makeRows(from: bottomLines, prefix: "collapsed-bottom-\(context.id)")) { row in
            switch row.kind {
            case .line(let line):
                DiffHighlighter(line: line, baseURL: baseURL)
            case .imagePair(let before, let after):
                ImageDiffPairView(before: before, after: after)
            }
            Divider().opacity(0.3)
        }
    }
}

private extension DiffLineType {
    var signature: String {
        switch self {
        case .unchanged:
            return "u"
        case .added:
            return "a"
        case .removed:
            return "r"
        }
    }
}

private enum DiffSection: Identifiable {
    case rows(id: Int, rows: [DiffRenderableRow])
    case collapsed(CollapsedContextSection)

    var id: Int {
        switch self {
        case .rows(let id, _):
            return id
        case .collapsed(let context):
            return context.id
        }
    }
}

private struct CollapsedContextSection: Identifiable {
    let id: Int
    let hiddenLines: [DiffLine]
    let canExpandTop: Bool
    let canExpandBottom: Bool
}

private struct DiffRenderableRow: Identifiable {
    let id: String
    let kind: DiffRenderableRowKind
}

private enum DiffRenderableRowKind {
    case line(DiffLine)
    case imagePair(before: MarkdownImageReference, after: MarkdownImageReference)
}

private struct ImageDiffPairView: View {
    let before: MarkdownImageReference
    let after: MarkdownImageReference

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("이미지 변경", systemImage: "photo.on.rectangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .top, spacing: 12) {
                imageColumn(title: "Before", reference: before, tint: .red)
                imageColumn(title: "After", reference: after, tint: .green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
    }

    private func imageColumn(title: String, reference: MarkdownImageReference, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            MarkdownImagePreview(reference: reference, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(reference.source)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
