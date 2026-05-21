import Foundation
import GhosttyTheme

struct GhosttyConfig {
    let url: URL
    let contents: String
    let fontFamilies: [String]
    let fontSize: Float?
    let colorTheme: TerminalAppTheme?
    let textKeybinds: [GhosttyTextKeybind]

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
            fontSize: parseFontSize(from: contents),
            colorTheme: parseColorTheme(from: contents),
            textKeybinds: parseTextKeybinds(from: contents)
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

    static func parseColorTheme(from contents: String) -> TerminalAppTheme? {
        if let inlineTheme = parseInlineColorTheme(from: contents) {
            return TerminalAppTheme(single: inlineTheme)
        }

        for value in parseValues(forKey: "theme", from: contents).reversed() {
            if let theme = parseNamedColorTheme(from: value) {
                return theme
            }
        }

        return nil
    }

    static func parseTextKeybinds(from contents: String) -> [GhosttyTextKeybind] {
        parseValues(forKey: "keybind", from: contents).compactMap(GhosttyTextKeybind.init(rawValue:))
    }

    private static func parseInlineColorTheme(from contents: String) -> TerminalColorTheme? {
        guard
            let background = parseLastValue(forKey: "background", from: contents),
            let foreground = parseLastValue(forKey: "foreground", from: contents)
        else {
            return nil
        }

        return TerminalColorTheme(
            name: "Ghostty Config",
            background: background,
            foreground: foreground,
            cursorColor: parseLastValue(forKey: "cursor-color", from: contents),
            selectionBackground: parseLastValue(forKey: "selection-background", from: contents),
            selectionForeground: parseLastValue(forKey: "selection-foreground", from: contents),
            palette: parsePalette(from: contents)
        )
    }

    private static func parseNamedColorTheme(from value: String) -> TerminalAppTheme? {
        let trimmed = stripQuotes(value)
        let components = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var light: TerminalColorTheme?
        var dark: TerminalColorTheme?

        for component in components {
            let parts = component.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let themeName = stripQuotes(String(parts[1]))
            guard let colorTheme = catalogTheme(named: themeName) else { continue }

            if key == "light" {
                light = colorTheme
            } else if key == "dark" {
                dark = colorTheme
            }
        }

        if light != nil || dark != nil {
            return TerminalAppTheme(light: light, dark: dark)
        }

        guard let colorTheme = catalogTheme(named: trimmed) else { return nil }
        return TerminalAppTheme(single: colorTheme)
    }

    private static func catalogTheme(named name: String) -> TerminalColorTheme? {
        let normalizedName = normalizeThemeName(name)
        let definition = GhosttyThemeCatalog.allThemes.first {
            normalizeThemeName($0.name) == normalizedName
        }

        guard let definition else { return nil }

        return TerminalColorTheme(
            name: definition.name,
            background: definition.background,
            foreground: definition.foreground,
            cursorColor: definition.cursorColor,
            selectionBackground: definition.selectionBackground,
            selectionForeground: definition.selectionForeground,
            palette: definition.palette
        )
    }

    private static func parsePalette(from contents: String) -> [Int: String] {
        parseValues(forKey: "palette", from: contents).reduce(into: [:]) { palette, value in
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let color = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(key), !color.isEmpty else { return }
            palette[index] = color
        }
    }

    private static func parseLastValue(forKey key: String, from contents: String) -> String? {
        parseValues(forKey: key, from: contents).last
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

    private static func stripQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        let first = trimmed.first
        let last = trimmed.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }

        return trimmed
    }

    private static func normalizeThemeName(_ name: String) -> String {
        stripQuotes(name)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

struct GhosttyTextKeybind: Equatable {
    let key: String
    let modifiers: EventModifierMask
    let text: String

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let keyChord = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let action = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard action.hasPrefix("text:") else { return nil }

        let chordParts = keyChord
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let key = chordParts.last, !key.isEmpty else { return nil }

        var modifiers: EventModifierMask = []
        for modifier in chordParts.dropLast() {
            switch modifier {
            case "cmd", "command":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "ctrl", "control":
                modifiers.insert(.control)
            case "alt", "option", "opt":
                modifiers.insert(.option)
            default:
                return nil
            }
        }

        self.key = key
        self.modifiers = modifiers
        self.text = Self.decodeGhosttyText(String(action.dropFirst("text:".count)))
    }

    func matches(key: String, modifiers: EventModifierMask) -> Bool {
        self.key == Self.normalizeKey(key) && self.modifiers == modifiers
    }

    private static func normalizeKey(_ key: String) -> String {
        switch key.lowercased() {
        case "=":
            return "equal"
        case "\r", "return":
            return "enter"
        default:
            return key.lowercased()
        }
    }

    private static func decodeGhosttyText(_ value: String) -> String {
        var decoded = ""
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                decoded.append(character)
                index = value.index(after: index)
                continue
            }

            let nextIndex = value.index(after: index)
            guard nextIndex < value.endIndex else {
                decoded.append(character)
                index = nextIndex
                continue
            }

            switch value[nextIndex] {
            case "x":
                let firstHexIndex = value.index(after: nextIndex)
                guard firstHexIndex < value.endIndex else {
                    decoded.append("\\x")
                    index = firstHexIndex
                    continue
                }

                let secondHexIndex = value.index(after: firstHexIndex)
                guard secondHexIndex < value.endIndex else {
                    decoded.append("\\x")
                    decoded.append(value[firstHexIndex])
                    index = secondHexIndex
                    continue
                }

                let hex = String(value[firstHexIndex...secondHexIndex])
                if let scalar = UInt8(hex, radix: 16) {
                    decoded.append(Character(UnicodeScalar(scalar)))
                    index = value.index(after: secondHexIndex)
                } else {
                    decoded.append("\\x")
                    index = firstHexIndex
                }
            case "r":
                decoded.append("\r")
                index = value.index(after: nextIndex)
            case "n":
                decoded.append("\n")
                index = value.index(after: nextIndex)
            case "t":
                decoded.append("\t")
                index = value.index(after: nextIndex)
            case "\\":
                decoded.append("\\")
                index = value.index(after: nextIndex)
            default:
                decoded.append(value[nextIndex])
                index = value.index(after: nextIndex)
            }
        }

        return decoded
    }
}

struct EventModifierMask: OptionSet, Equatable {
    let rawValue: Int

    static let command = EventModifierMask(rawValue: 1 << 0)
    static let shift = EventModifierMask(rawValue: 1 << 1)
    static let control = EventModifierMask(rawValue: 1 << 2)
    static let option = EventModifierMask(rawValue: 1 << 3)
}
