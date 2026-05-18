import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var document: MarkdownDocument
    var showsInlineToolbar = true
    var rendersMarkdownStyle = false

    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownTextEditor(
                text: $document.editableContent,
                selectedRange: $selectedRange,
                rendersMarkdownStyle: rendersMarkdownStyle
            )

            if showsInlineToolbar, selectedRange.length > 0 {
                InlineEditToolbar { action in
                    apply(action)
                }
                .padding(.top, 18)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private func apply(_ action: MarkdownEditAction) {
        let text = document.editableContent
        let nsText = text as NSString
        let safeRange = NSIntersectionRange(
            selectedRange,
            NSRange(location: 0, length: nsText.length)
        )

        guard safeRange.location != NSNotFound else { return }

        switch action {
        case .heading:
            replaceLineRange(in: nsText, selection: safeRange) { lines in
                lines
                    .components(separatedBy: "\n")
                    .map { line in
                        line.hasPrefix("# ") ? String(line.dropFirst(2)) : "# \(line)"
                    }
                    .joined(separator: "\n")
            }
        case .bold:
            wrapSelection(prefix: "**", suffix: "**", placeholder: "굵은 텍스트", range: safeRange)
        case .italic:
            wrapSelection(prefix: "*", suffix: "*", placeholder: "기울임 텍스트", range: safeRange)
        case .link:
            wrapSelection(prefix: "[", suffix: "](url)", placeholder: "링크", range: safeRange)
        case .unorderedList:
            prefixSelectedLines("- ", range: safeRange)
        case .orderedList:
            prefixSelectedLines(numbered: true, range: safeRange)
        case .checklist:
            prefixSelectedLines("- [ ] ", range: safeRange)
        case .quote:
            prefixSelectedLines("> ", range: safeRange)
        case .inlineCode:
            wrapSelection(prefix: "`", suffix: "`", placeholder: "code", range: safeRange)
        }
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String, range: NSRange) {
        let nsText = document.editableContent as NSString
        let selected = range.length > 0 ? nsText.substring(with: range) : placeholder
        let replacement = "\(prefix)\(selected)\(suffix)"
        document.editableContent = nsText.replacingCharacters(in: range, with: replacement)
        selectedRange = NSRange(location: range.location + prefix.count, length: selected.count)
    }

    private func prefixSelectedLines(_ prefix: String, range: NSRange) {
        replaceLineRange(in: document.editableContent as NSString, selection: range) { lines in
            lines
                .components(separatedBy: "\n")
                .map { $0.isEmpty ? prefix : "\(prefix)\($0)" }
                .joined(separator: "\n")
        }
    }

    private func prefixSelectedLines(numbered: Bool, range: NSRange) {
        guard numbered else { return }
        replaceLineRange(in: document.editableContent as NSString, selection: range) { lines in
            lines
                .components(separatedBy: "\n")
                .enumerated()
                .map { index, line in "\(index + 1). \(line)" }
                .joined(separator: "\n")
        }
    }

    private func replaceLineRange(
        in nsText: NSString,
        selection: NSRange,
        transform: (String) -> String
    ) {
        let lineRange = nsText.lineRange(for: selection)
        let selectedLines = nsText.substring(with: lineRange)
        let replacement = transform(selectedLines)
        document.editableContent = nsText.replacingCharacters(in: lineRange, with: replacement)
        selectedRange = NSRange(location: lineRange.location, length: (replacement as NSString).length)
    }
}

private enum MarkdownEditAction {
    case heading
    case bold
    case italic
    case link
    case unorderedList
    case orderedList
    case checklist
    case quote
    case inlineCode
}

private struct InlineEditToolbar: View {
    var onAction: (MarkdownEditAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            toolbarButton("H", help: "제목", action: .heading)
            toolbarButton("B", help: "굵게", action: .bold)
            toolbarButton("I", help: "기울임", action: .italic)
                .italic()
            toolbarButton(systemImage: "link", help: "링크", action: .link)
            toolbarButton(systemImage: "list.bullet", help: "글머리 기호", action: .unorderedList)
            toolbarButton(systemImage: "list.number", help: "번호 목록", action: .orderedList)
            toolbarButton(systemImage: "checklist", help: "체크리스트", action: .checklist)
            toolbarButton(systemImage: "quote.opening", help: "인용", action: .quote)
            toolbarButton(systemImage: "chevron.left.forwardslash.chevron.right", help: "인라인 코드", action: .inlineCode)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func toolbarButton(_ title: String, help: String, action: MarkdownEditAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 30)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toolbarButton(systemImage: String, help: String, action: MarkdownEditAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 30)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let rendersMarkdownStyle: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedRange: $selectedRange,
            rendersMarkdownStyle: rendersMarkdownStyle
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.font = rendersMarkdownStyle
            ? .systemFont(ofSize: 18)
            : .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        context.coordinator.applyMarkdownStyle(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        context.coordinator.rendersMarkdownStyle = rendersMarkdownStyle
        context.coordinator.applyMarkdownStyle(to: textView)

        let textLength = (textView.string as NSString).length
        let safeLocation = min(selectedRange.location, textLength)
        let safeLength = min(selectedRange.length, textLength - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        if textView.selectedRange() != safeRange {
            textView.setSelectedRange(safeRange)
        }

        if scrollView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        var rendersMarkdownStyle: Bool

        init(
            text: Binding<String>,
            selectedRange: Binding<NSRange>,
            rendersMarkdownStyle: Bool
        ) {
            _text = text
            _selectedRange = selectedRange
            self.rendersMarkdownStyle = rendersMarkdownStyle
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            applyMarkdownStyle(to: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectedRange = textView.selectedRange()
        }

        @MainActor
        func applyMarkdownStyle(to textView: NSTextView) {
            let selection = textView.selectedRange()
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            let fontSize: CGFloat = rendersMarkdownStyle ? 18 : NSFont.systemFontSize
            let baseFont = rendersMarkdownStyle
                ? NSFont.systemFont(ofSize: fontSize)
                : NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributes(
                [
                    .font: baseFont,
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: paragraphStyle(lineSpacing: rendersMarkdownStyle ? 7 : 2)
                ],
                range: fullRange
            )

            if rendersMarkdownStyle {
                applyPreviewAttributes(to: textView, fullRange: fullRange)
            }

            textView.textStorage?.endEditing()
            textView.setSelectedRange(selection)
        }

        @MainActor
        private func applyPreviewAttributes(to textView: NSTextView, fullRange: NSRange) {
            let nsText = textView.string as NSString
            applyHeadingAttributes(text: nsText, textView: textView, fullRange: fullRange)
            applyDelimitedAttributes(
                pattern: #"\*\*([^*]+)\*\*"#,
                textView: textView,
                fullRange: fullRange,
                contentAttributes: [.font: NSFont.boldSystemFont(ofSize: 18)]
            )
            applyDelimitedAttributes(
                pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#,
                textView: textView,
                fullRange: fullRange,
                contentAttributes: [
                    .font: NSFontManager.shared.convert(
                        NSFont.systemFont(ofSize: 18),
                        toHaveTrait: .italicFontMask
                    )
                ]
            )
            applyDelimitedAttributes(
                pattern: #"`([^`]+)`"#,
                textView: textView,
                fullRange: fullRange,
                contentAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular),
                    .foregroundColor: NSColor.systemPink
                ]
            )
            applyLinkAttributes(textView: textView, fullRange: fullRange)
            applyListAttributes(text: nsText, textView: textView, fullRange: fullRange)
            applyQuoteAttributes(text: nsText, textView: textView, fullRange: fullRange)
            applyThematicBreakAttributes(text: nsText, textView: textView, fullRange: fullRange)
            applyTableAttributes(text: nsText, textView: textView, fullRange: fullRange)
        }

        @MainActor
        private func applyHeadingAttributes(
            text: NSString,
            textView: NSTextView,
            fullRange: NSRange
        ) {
            guard let regex = try? NSRegularExpression(
                pattern: #"^(#{1,6})(\s+)(.+)$"#,
                options: [.anchorsMatchLines]
            ) else { return }

            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                let level = text.substring(with: match.range(at: 1)).count
                let fontSize: CGFloat
                switch level {
                case 1: fontSize = 34
                case 2: fontSize = 28
                case 3: fontSize = 24
                case 4: fontSize = 21
                default: fontSize = 18
                }

                textView.textStorage?.addAttributes(
                    [
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.labelColor
                    ],
                    range: match.range(at: 3)
                )
                hideSyntax(in: match.range(at: 1), textView: textView)
                hideSyntax(in: match.range(at: 2), textView: textView)
            }
        }

        @MainActor
        private func applyDelimitedAttributes(
            pattern: String,
            textView: NSTextView,
            fullRange: NSRange,
            contentAttributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

            regex.enumerateMatches(in: textView.string, range: fullRange) { match, _, _ in
                guard let match else { return }
                let contentRange = match.range(at: 1)
                textView.textStorage?.addAttributes(contentAttributes, range: contentRange)

                if match.range.location < contentRange.location {
                    hideSyntax(
                        in: NSRange(
                            location: match.range.location,
                            length: contentRange.location - match.range.location
                        ),
                        textView: textView
                    )
                }

                let endLocation = contentRange.location + contentRange.length
                let matchEndLocation = match.range.location + match.range.length
                if endLocation < matchEndLocation {
                    hideSyntax(
                        in: NSRange(
                            location: endLocation,
                            length: matchEndLocation - endLocation
                        ),
                        textView: textView
                    )
                }
            }
        }

        @MainActor
        private func applyLinkAttributes(textView: NSTextView, fullRange: NSRange) {
            guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else { return }

            regex.enumerateMatches(in: textView.string, range: fullRange) { match, _, _ in
                guard let match else { return }
                let titleRange = match.range(at: 1)
                textView.textStorage?.addAttributes(
                    [
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: titleRange
                )

                hideSyntax(in: NSRange(location: match.range.location, length: 1), textView: textView)
                hideSyntax(
                    in: NSRange(
                        location: titleRange.location + titleRange.length,
                        length: match.range.location + match.range.length - titleRange.location - titleRange.length
                    ),
                    textView: textView
                )
            }
        }

        @MainActor
        private func applyListAttributes(text: NSString, textView: NSTextView, fullRange: NSRange) {
            guard let regex = try? NSRegularExpression(
                pattern: #"^(\s*)(-|\d+\.|- \[[ xX]\])(\s+)(.+)$"#,
                options: [.anchorsMatchLines]
            ) else { return }

            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                textView.textStorage?.addAttributes(
                    [.foregroundColor: NSColor.labelColor],
                    range: match.range(at: 4)
                )
                hideSyntax(in: match.range(at: 2), textView: textView)
                hideSyntax(in: match.range(at: 3), textView: textView)
            }
        }

        @MainActor
        private func applyQuoteAttributes(text: NSString, textView: NSTextView, fullRange: NSRange) {
            guard let regex = try? NSRegularExpression(
                pattern: #"^(\s*>)(\s+)(.+)$"#,
                options: [.anchorsMatchLines]
            ) else { return }

            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                textView.textStorage?.addAttributes(
                    [.foregroundColor: NSColor.secondaryLabelColor],
                    range: match.range(at: 3)
                )
                hideSyntax(in: match.range(at: 1), textView: textView)
                hideSyntax(in: match.range(at: 2), textView: textView)
            }
        }

        @MainActor
        private func applyThematicBreakAttributes(text: NSString, textView: NSTextView, fullRange: NSRange) {
            guard let regex = try? NSRegularExpression(
                pattern: #"^\s{0,3}([-*_])(?:\s*\1){2,}\s*$"#,
                options: [.anchorsMatchLines]
            ) else { return }

            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match else { return }
                textView.textStorage?.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                        .foregroundColor: NSColor.separatorColor,
                        .kern: 3
                    ],
                    range: match.range
                )
            }
        }

        @MainActor
        private func applyTableAttributes(text: NSString, textView: NSTextView, fullRange: NSRange) {
            let fullString = text as String
            let lines = fullString.components(separatedBy: "\n")
            var location = 0

            for index in lines.indices {
                let line = lines[index]
                let lineLength = (line as NSString).length
                let lineRange = NSRange(location: location, length: lineLength)
                defer {
                    location += lineLength
                    if index < lines.count - 1 {
                        location += 1
                    }
                }

                guard NSLocationInRange(lineRange.location, fullRange),
                      line.contains("|") else {
                    continue
                }

                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let isSeparator = trimmed.range(
                    of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#,
                    options: .regularExpression
                ) != nil

                textView.textStorage?.addAttributes(
                    [
                        .font: NSFont.monospacedSystemFont(ofSize: isSeparator ? 12 : 17, weight: .regular),
                        .paragraphStyle: paragraphStyle(lineSpacing: 3)
                    ],
                    range: lineRange
                )

                if isSeparator {
                    textView.textStorage?.addAttributes(
                        [
                            .foregroundColor: NSColor.separatorColor,
                            .kern: 1.5
                        ],
                        range: lineRange
                    )
                } else if isLikelyTableHeader(lines: lines, index: index) {
                    textView.textStorage?.addAttributes(
                        [.font: NSFont.monospacedSystemFont(ofSize: 17, weight: .bold)],
                        range: lineRange
                    )
                }

                applyTablePipeAttributes(in: lineRange, text: text, textView: textView)
            }
        }

        private func isLikelyTableHeader(lines: [String], index: Int) -> Bool {
            guard index + 1 < lines.count else { return false }
            return lines[index + 1].trimmingCharacters(in: .whitespaces).range(
                of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#,
                options: .regularExpression
            ) != nil
        }

        @MainActor
        private func applyTablePipeAttributes(in lineRange: NSRange, text: NSString, textView: NSTextView) {
            let line = text.substring(with: lineRange) as NSString
            var searchLocation = 0

            while searchLocation < line.length {
                let pipeRange = line.range(
                    of: "|",
                    options: [],
                    range: NSRange(location: searchLocation, length: line.length - searchLocation)
                )
                guard pipeRange.location != NSNotFound else { break }

                textView.textStorage?.addAttributes(
                    [.foregroundColor: NSColor.separatorColor],
                    range: NSRange(location: lineRange.location + pipeRange.location, length: pipeRange.length)
                )
                searchLocation = pipeRange.location + pipeRange.length
            }
        }

        @MainActor
        private func hideSyntax(in range: NSRange, textView: NSTextView) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            textView.textStorage?.addAttributes(hiddenSyntaxAttributes, range: range)
        }

        private var hiddenSyntaxAttributes: [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: 0.1),
                .foregroundColor: NSColor.clear
            ]
        }

        private func paragraphStyle(lineSpacing: CGFloat) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = lineSpacing
            return style
        }
    }
}
