import Foundation
import GhosttyTheme

struct GhosttyConfig {
    static let defaultFallbackFontFamily = "Apple SD Gothic Neo"

    let url: URL
    let contents: String
    let fontFamilies: [String]
    let fontSize: Float?
    let colorTheme: TerminalAppTheme?
    let keybinds: [GhosttyKeybind]

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
            fontFamilies: fontFamiliesWithDefaultFallback(from: contents),
            fontSize: parseFontSize(from: contents),
            colorTheme: parseColorTheme(from: contents),
            keybinds: parseKeybinds(from: contents)
        )
    }

    static func parseFontFamilies(from contents: String) -> [String] {
        parseValues(forKey: "font-family", from: contents)
    }

    static func parseFontFamilyNames(from contents: String) -> [String] {
        parseFontFamilies(from: contents).map(stripQuotes)
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

    static func parseThemeName(from contents: String) -> String? {
        parseValues(forKey: "theme", from: contents)
            .reversed()
            .compactMap { value in
                themeName(from: value)
            }
            .first
    }

    static func parseKeybinds(from contents: String) -> [GhosttyKeybind] {
        parseValues(forKey: "keybind", from: contents).compactMap(GhosttyKeybind.init(rawValue:))
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

    static func preferences(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> GhosttyPreferences {
        let config = userConfig(fileManager: fileManager, homeDirectory: homeDirectory)
        let contents = config?.contents ?? ""
        let fontFamilies = parseFontFamilyNames(from: contents)

        return GhosttyPreferences(
            configURL: config?.url ?? defaultConfigURL(homeDirectory: homeDirectory),
            themeName: parseThemeName(from: contents) ?? "Dark Modern",
            fontSize: Double(parseFontSize(from: contents) ?? 14),
            primaryFontFamily: fontFamilies.first ?? "Menlo",
            fallbackFontFamily: fontFamilies.dropFirst().first ?? defaultFallbackFontFamily
        )
    }

    static func writePreferences(
        _ preferences: GhosttyPreferences,
        fileManager: FileManager = .default
    ) throws {
        let url = preferences.configURL
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = updatingPreferences(preferences, in: contents)

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    static func updatingPreferences(_ preferences: GhosttyPreferences, in contents: String) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let generatedLines = [
            "theme = \(preferences.themeName)",
            "font-size = \(formatFontSize(preferences.fontSize))",
        ] + preferences.fontFamilyLines

        lines = replacingActiveLines(forKeys: ["theme", "font-size", "font-family"], in: lines, with: generatedLines)

        var updated = lines.joined(separator: "\n")
        if !updated.isEmpty, !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        return updated
    }

    static func defaultConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".config/ghostty/config")
    }

    static func stripQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        let first = trimmed.first
        let last = trimmed.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }

        return trimmed
    }

    private static func themeName(from value: String) -> String? {
        let trimmed = stripQuotes(value)
        let components = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for preferredKey in ["dark", "light"] {
            for component in components {
                let parts = component.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard key == preferredKey else { continue }
                return stripQuotes(String(parts[1]))
            }
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    private static func replacingActiveLines(forKeys keys: Set<String>, in lines: [String], with replacement: [String]) -> [String] {
        var result: [String] = []
        var didInsert = false

        for line in lines {
            guard let key = activeKey(in: line), keys.contains(key) else {
                result.append(line)
                continue
            }

            if !didInsert {
                result.append(contentsOf: replacement)
                didInsert = true
            }
        }

        if !didInsert {
            if !result.isEmpty, result.last?.isEmpty == false {
                result.append("")
            }
            result.append(contentsOf: replacement)
        }

        return result
    }

    private static func activeKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return parts[0].trimmingCharacters(in: .whitespaces)
    }

    private static func formatFontSize(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private static func normalizeThemeName(_ name: String) -> String {
        stripQuotes(name)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func fontFamiliesWithDefaultFallback(from contents: String) -> [String] {
        let families = parseFontFamilies(from: contents)
        guard families.count == 1 else { return families }

        let fallbackLine = "\"\(defaultFallbackFontFamily)\""
        if families.contains(where: { stripQuotes($0) == defaultFallbackFontFamily }) {
            return families
        }

        return families + [fallbackLine]
    }
}

struct GhosttyPreferences: Equatable {
    let configURL: URL
    var themeName: String
    var fontSize: Double
    var primaryFontFamily: String
    var fallbackFontFamily: String

    var fontFamilyLines: [String] {
        [primaryFontFamily, fallbackFontFamily]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "font-family = \"\($0)\"" }
    }
}

struct GhosttyKeybind: Equatable {
    let key: String
    let modifiers: EventModifierMask
    let action: String

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let keyChord = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let action = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        self.action = action
    }

    func matches(key: String, modifiers: EventModifierMask) -> Bool {
        self.key == Self.normalizeKey(key) && self.modifiers == modifiers
    }

    var decodedTextAction: String? {
        guard action.hasPrefix("text:") else { return nil }
        return Self.decodeGhosttyText(String(action.dropFirst("text:".count)))
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
