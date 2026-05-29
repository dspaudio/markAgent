import HighlightSwift
import AppKit
import SwiftUI

struct HighlightedCodeBlock: View {
    let code: String
    let language: String?

    @State private var attributedCode: AttributedString?
    @State private var isHoveringBadge = false
    @State private var didCopy = false
    @Environment(\.colorScheme) private var colorScheme

    private static let highlighter = Highlight()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                if let attributedCode {
                    SwiftUI.Text(attributedCode)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SwiftUI.Text(code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            badge
        }
        .background(codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.18))
        )
        .padding(.bottom, 8)
        .task(id: HashableHighlightInput(code: code, language: language, scheme: colorScheme)) {
            await highlight()
        }
    }

    private var badge: some View {
        Button {
            copyCode()
        } label: {
            Group {
                if didCopy {
                    SwiftUI.Image(systemName: "checkmark")
                        .imageScale(.small)
                } else if isHoveringBadge {
                    SwiftUI.Image(systemName: "doc.on.doc")
                        .imageScale(.small)
                } else {
                    SwiftUI.Text("<\(displayLanguage)>")
                        .font(.caption2.monospaced())
                }
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 42, minHeight: 18)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "코드 복사"))
        .padding(8)
        .onHover { hovering in
            isHoveringBadge = hovering
            if hovering {
                didCopy = false
            }
        }
    }

    private func highlight() async {
        guard let language, !language.isEmpty, !Self.plainTextLanguages.contains(language.lowercased()) else {
            attributedCode = nil
            return
        }

        let colors: HighlightColors = colorScheme == .dark ? .dark(.xcode) : .light(.xcode)
        do {
            let result = try await Self.highlighter.attributedText(code, language: language, colors: colors)
            attributedCode = result
        } catch {
            attributedCode = nil
        }
    }

    private static let plainTextLanguages: Set<String> = [
        "text",
        "txt",
        "plain",
        "plaintext",
        "ascii"
    ]

    private var displayLanguage: String {
        guard let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "code"
        }
        return language.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var codeBlockBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : Color(red: 0.94, green: 0.94, blue: 0.95)
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        didCopy = true
    }
}

private struct HashableHighlightInput: Hashable {
    let code: String
    let language: String?
    let scheme: ColorScheme
}
