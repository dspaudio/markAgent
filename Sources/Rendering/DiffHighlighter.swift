import SwiftUI

struct DiffHighlighter: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            gutterView
            markerView
            contentView
        }
        .background(backgroundColor)
    }

    // MARK: - 하위 뷰

    private var gutterView: some View {
        HStack(spacing: 0) {
            switch line.type {
            case .removed:
                lineNumberText(line.oldLineNumber)
                lineNumberText(nil)
            case .added:
                lineNumberText(nil)
                lineNumberText(line.lineNumber)
            case .unchanged:
                lineNumberText(line.oldLineNumber)
                lineNumberText(line.lineNumber)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.tertiary)
    }

    private func lineNumberText(_ number: Int?) -> some View {
        Text(number.map { "\($0)" } ?? "")
            .frame(width: 36, alignment: .trailing)
            .padding(.horizontal, 4)
    }

    private var markerView: some View {
        Text(marker)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(markerColor)
            .frame(width: 18, alignment: .center)
    }

    private var contentView: some View {
        Text(line.content)
            .font(.system(size: 13, design: .monospaced))
            .strikethrough(line.type == .removed, color: .secondary)
            .foregroundStyle(line.type == .removed ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .textSelection(.enabled)
    }

    // MARK: - 헬퍼

    private var marker: String {
        switch line.type {
        case .added:     return "+"
        case .removed:   return "-"
        case .unchanged: return " "
        }
    }

    private var markerColor: Color {
        switch line.type {
        case .added:     return .green
        case .removed:   return .red
        case .unchanged: return .clear
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added:     return .green.opacity(0.15)
        case .removed:   return .red.opacity(0.15)
        case .unchanged: return .clear
        }
    }
}
