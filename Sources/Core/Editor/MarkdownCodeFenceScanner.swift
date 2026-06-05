import Foundation

struct MarkdownCodeFence: Equatable {
    let openingRange: NSRange
    let codeRange: NSRange
    let closingRange: NSRange?
    let language: String?
}

enum MarkdownCodeFenceScanner {
    static func fences(in text: String) -> [MarkdownCodeFence] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(
            pattern: #"^(```|~~~)([^\r\n]*)$"#,
            options: [.anchorsMatchLines]
        ) else {
            return []
        }

        let matches = regex.matches(in: text, range: fullRange)
        var fences: [MarkdownCodeFence] = []
        var openMatch: NSTextCheckingResult?
        var openMarker = ""

        for match in matches {
            let lineRange = nsText.lineRange(for: match.range)
            let linePrefix = nsText.substring(
                with: NSRange(location: lineRange.location, length: match.range.location - lineRange.location)
            )
            guard linePrefix.isEmpty else { continue }

            let marker = nsText.substring(with: match.range(at: 1))
            if let opening = openMatch {
                guard marker == openMarker else { continue }
                fences.append(
                    MarkdownCodeFence(
                        openingRange: opening.range,
                        codeRange: codeRange(in: nsText, openingRange: opening.range, closingRange: match.range),
                        closingRange: match.range,
                        language: language(from: opening, in: nsText)
                    )
                )
                openMatch = nil
                openMarker = ""
            } else {
                openMatch = match
                openMarker = marker
            }
        }

        if let opening = openMatch {
            fences.append(
                MarkdownCodeFence(
                    openingRange: opening.range,
                    codeRange: codeRange(in: nsText, openingRange: opening.range, closingRange: nil),
                    closingRange: nil,
                    language: language(from: opening, in: nsText)
                )
            )
        }

        return fences
    }

    private static func codeRange(
        in text: NSString,
        openingRange: NSRange,
        closingRange: NSRange?
    ) -> NSRange {
        let openingLineRange = text.lineRange(for: openingRange)
        let start = openingLineRange.location + openingLineRange.length
        let end = closingRange?.location ?? text.length
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func language(from match: NSTextCheckingResult, in text: NSString) -> String? {
        let rawLanguage = text
            .substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawLanguage.isEmpty else { return nil }
        return rawLanguage.components(separatedBy: .whitespaces).first
    }
}
