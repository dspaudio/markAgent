import HighlightSwift
import SwiftUI

struct HighlightedCodeBlock: View {
    let code: String
    let language: String?

    @State private var attributedCode: AttributedString?
    @Environment(\.colorScheme) private var colorScheme

    private static let highlighter = Highlight()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if let attributedCode {
                SwiftUI.Text(attributedCode)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SwiftUI.Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 8)
        .task(id: HashableHighlightInput(code: code, language: language, scheme: colorScheme)) {
            await highlight()
        }
    }

    private func highlight() async {
        let colors: HighlightColors = colorScheme == .dark ? .dark(.xcode) : .light(.xcode)
        do {
            let result: AttributedString
            if let language, !language.isEmpty {
                result = try await Self.highlighter.attributedText(code, language: language, colors: colors)
            } else {
                result = try await Self.highlighter.attributedText(code, colors: colors)
            }
            attributedCode = result
        } catch {
            attributedCode = nil
        }
    }
}

private struct HashableHighlightInput: Hashable {
    let code: String
    let language: String?
    let scheme: ColorScheme
}
