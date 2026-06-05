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
    @Environment(\.terminalAppTheme) private var terminalAppTheme

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
        .task(id: HashableHighlightInput(code: code, language: language, scheme: colorScheme, colorSignature: colorSignature)) {
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

        let colors = highlightColors
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
        if let appColors {
            return Color(nsColor: appColors.textBackground.blended(withFraction: 0.08, of: appColors.syntaxBlue) ?? appColors.textBackground)
        }
        return colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : Color(red: 0.94, green: 0.94, blue: 0.95)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.theme(for: colorScheme)?.appColors()
    }

    private var highlightColors: HighlightColors {
        guard let appColors else {
            return colorScheme == .dark ? .dark(.xcode) : .light(.xcode)
        }
        return .custom(css: appColors.highlightCSS, background: appColors.textBackground.hexRGB)
    }

    private var colorSignature: String {
        guard let appColors else { return "xcode-\(colorScheme)" }
        return [
            appColors.textForeground.hexRGB,
            appColors.textBackground.hexRGB,
            appColors.syntaxGreen.hexRGB,
            appColors.syntaxBlue.hexRGB,
            appColors.syntaxMagenta.hexRGB
        ].joined(separator: "|")
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
    let colorSignature: String
}

extension TerminalAppColors {
    var highlightCSS: String {
        let foreground = textForeground.hexRGB
        let comment = textForeground.withAlphaComponent(0.62).hexRGB
        let string = syntaxGreen.hexRGB
        let number = syntaxYellow.hexRGB
        let tag = syntaxBlue.hexRGB
        let keyword = syntaxMagenta.hexRGB
        let red = syntaxRed.hexRGB
        let cyan = syntaxCyan.hexRGB

        return """
        pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#\(foreground)}.hljs-comment,.hljs-quote{color:#\(comment)}.hljs-addition,.hljs-string,.hljs-symbol{color:#\(string)}.hljs-attr,.hljs-attribute,.hljs-literal,.hljs-number,.hljs-variable{color:#\(number)}.hljs-keyword,.hljs-selector-tag,.hljs-template-tag,.hljs-type{color:#\(keyword)}.hljs-name,.hljs-section,.hljs-title,.hljs-title.function_{color:#\(tag)}.hljs-tag,.hljs-deletion{color:#\(red)}.hljs-built_in,.hljs-link,.hljs-meta{color:#\(cyan)}.hljs-emphasis{font-style:italic}.hljs-strong{font-weight:700}
        """
    }
}

extension NSColor {
    var hexRGB: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "%02x%02x%02x",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
