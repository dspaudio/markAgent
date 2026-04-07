import SwiftUI

struct DiffOverlayView: View {
    let diffResult: DiffResult
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
                ForEach(Array(diffResult.lines.enumerated()), id: \.offset) { _, line in
                    DiffHighlighter(line: line)
                    Divider()
                        .opacity(0.3)
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
}
