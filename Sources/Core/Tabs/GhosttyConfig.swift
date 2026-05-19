import Foundation

struct GhosttyConfig {
    let url: URL
    let contents: String
    let fontFamilies: [String]
    let fontSize: Float?

    static func userConfig(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> GhosttyConfig? {
        let candidates = [
            homeDirectory
                .appendingPathComponent(".config/ghostty/config"),
            homeDirectory
                .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config"),
        ]

        guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }

        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return GhosttyConfig(
            url: url,
            contents: contents,
            fontFamilies: parseFontFamilies(from: contents),
            fontSize: parseFontSize(from: contents)
        )
    }

    static func parseFontFamilies(from contents: String) -> [String] {
        parseValues(forKey: "font-family", from: contents)
    }

    static func parseFontSize(from contents: String) -> Float? {
        parseValues(forKey: "font-size", from: contents)
            .reversed()
            .compactMap(Float.init)
            .first
    }

    private static func parseValues(forKey targetKey: String, from contents: String) -> [String] {
        contents.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard key == targetKey else { return nil }

            let value = parts[1].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
    }
}
