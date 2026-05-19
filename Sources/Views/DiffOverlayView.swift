import SwiftUI

struct DiffOverlayView: View {
    let diffResult: DiffResult
    var baseURL: URL?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            diffList
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
                ForEach(diffRows, id: \.id) { row in
                    switch row {
                    case .line(let id, let line):
                        DiffHighlighter(line: line, baseURL: baseURL)
                            .id(id)
                    case .imagePair(let id, let before, let after):
                        ImageDiffPairView(before: before, after: after)
                            .id(id)
                    }
                    Divider().opacity(0.3)
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

    private var diffRows: [DiffRow] {
        var rows: [DiffRow] = []
        var index = 0
        while index < diffResult.lines.count {
            let line = diffResult.lines[index]
            if line.type == .removed,
               index + 1 < diffResult.lines.count,
               diffResult.lines[index + 1].type == .added,
               let before = MarkdownImageLineParser.firstImage(in: line.content, baseURL: baseURL),
               let after = MarkdownImageLineParser.firstImage(in: diffResult.lines[index + 1].content, baseURL: baseURL) {
                rows.append(.imagePair(id: index, before: before, after: after))
                index += 2
            } else {
                rows.append(.line(id: index, line: line))
                index += 1
            }
        }
        return rows
    }
}

private enum DiffRow {
    case line(id: Int, line: DiffLine)
    case imagePair(id: Int, before: MarkdownImageReference, after: MarkdownImageReference)

    var id: Int {
        switch self {
        case .line(let id, _), .imagePair(let id, _, _): return id
        }
    }
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
