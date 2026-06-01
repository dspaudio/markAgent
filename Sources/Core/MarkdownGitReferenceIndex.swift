import Foundation

enum MarkdownGitReferenceIndex {
    static func mentionedFileIDs(in markdown: String, changedFiles: [GitChangedFile]) -> Set<GitChangedFile.ID> {
        guard !markdown.isEmpty, !changedFiles.isEmpty else { return [] }

        return Set(
            changedFiles.compactMap { file in
                contains(relativePath: file.relativePath, in: markdown) ? file.id : nil
            }
        )
    }

    private static func contains(relativePath: String, in markdown: String) -> Bool {
        guard !relativePath.isEmpty else { return false }

        let escapedPath = NSRegularExpression.escapedPattern(for: relativePath)
        let pattern = #"(?<![A-Za-z0-9_./-])"# + escapedPath + #"(?=$|[^A-Za-z0-9_./-]|:\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }

        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.firstMatch(in: markdown, range: range) != nil
    }
}
