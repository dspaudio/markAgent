import AppKit
import SwiftUI

struct TerminalAppTheme: Equatable {
    let light: TerminalColorTheme?
    let dark: TerminalColorTheme?

    init(light: TerminalColorTheme? = nil, dark: TerminalColorTheme? = nil) {
        self.light = light
        self.dark = dark
    }

    init(single theme: TerminalColorTheme) {
        self.light = theme
        self.dark = theme
    }

    var preferredColorScheme: ColorScheme? {
        guard light == dark, let theme = light else { return nil }
        return theme.isDark ? .dark : .light
    }

    func theme(for colorScheme: ColorScheme) -> TerminalColorTheme? {
        switch colorScheme {
        case .light:
            light ?? dark
        case .dark:
            dark ?? light
        @unknown default:
            dark ?? light
        }
    }
}

struct TerminalColorTheme: Equatable, Sendable {
    let name: String
    let background: String
    let foreground: String
    let cursorColor: String?
    let selectionBackground: String?
    let selectionForeground: String?
    let palette: [Int: String]

    var isDark: Bool {
        guard let color = NSColor(hexString: background) else { return true }
        return color.relativeLuminance < 0.5
    }

    func appColors() -> TerminalAppColors? {
        guard
            let backgroundColor = NSColor(hexString: background),
            let foregroundColor = NSColor(hexString: foreground)
        else {
            return nil
        }

        let accentColor = NSColor(hexString: palette[4] ?? cursorColor ?? selectionBackground ?? foreground)
            ?? foregroundColor
        let panelColor = backgroundColor.mixed(with: foregroundColor, fraction: isDark ? 0.08 : 0.05)
        let elevatedColor = backgroundColor.mixed(with: foregroundColor, fraction: isDark ? 0.13 : 0.09)
        let borderColor = backgroundColor.mixed(with: foregroundColor, fraction: isDark ? 0.22 : 0.18)
        let syntaxFallbackColor = backgroundColor.mixed(with: foregroundColor, fraction: isDark ? 0.72 : 0.58)

        return TerminalAppColors(
            background: Color(nsColor: backgroundColor),
            panel: Color(nsColor: panelColor),
            elevated: Color(nsColor: elevatedColor),
            foreground: Color(nsColor: foregroundColor),
            secondaryForeground: Color(nsColor: foregroundColor).opacity(0.68),
            border: Color(nsColor: borderColor),
            accent: Color(nsColor: accentColor),
            textBackground: backgroundColor,
            textForeground: foregroundColor,
            insertionPoint: accentColor,
            syntaxRed: paletteColor(primary: 1, bright: 9, fallback: syntaxFallbackColor),
            syntaxGreen: paletteColor(primary: 2, bright: 10, fallback: syntaxFallbackColor),
            syntaxYellow: paletteColor(primary: 3, bright: 11, fallback: syntaxFallbackColor),
            syntaxBlue: paletteColor(primary: 4, bright: 12, fallback: accentColor),
            syntaxMagenta: paletteColor(primary: 5, bright: 13, fallback: accentColor),
            syntaxCyan: paletteColor(primary: 6, bright: 14, fallback: accentColor)
        )
    }

    private func paletteColor(primary: Int, bright: Int, fallback: NSColor) -> NSColor {
        guard let hex = palette[primary] ?? palette[bright] else { return fallback }
        return NSColor(hexString: hex) ?? fallback
    }
}

struct TerminalAppColors {
    let background: Color
    let panel: Color
    let elevated: Color
    let foreground: Color
    let secondaryForeground: Color
    let border: Color
    let accent: Color
    let textBackground: NSColor
    let textForeground: NSColor
    let insertionPoint: NSColor
    let syntaxRed: NSColor
    let syntaxGreen: NSColor
    let syntaxYellow: NSColor
    let syntaxBlue: NSColor
    let syntaxMagenta: NSColor
    let syntaxCyan: NSColor
}

private struct TerminalAppThemeKey: EnvironmentKey {
    static let defaultValue: TerminalAppTheme? = nil
}

extension EnvironmentValues {
    var terminalAppTheme: TerminalAppTheme? {
        get { self[TerminalAppThemeKey.self] }
        set { self[TerminalAppThemeKey.self] = newValue }
    }
}

extension TerminalAppTheme {
    func colors(for colorScheme: ColorScheme) -> TerminalAppColors? {
        theme(for: colorScheme)?.appColors()
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        } else if value.lowercased().hasPrefix("0x") {
            value.removeFirst(2)
        }

        guard value.count == 6 || value.count == 8, let integer = UInt64(value, radix: 16) else {
            return nil
        }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        if value.count == 8 {
            red = CGFloat((integer >> 24) & 0xff) / 255
            green = CGFloat((integer >> 16) & 0xff) / 255
            blue = CGFloat((integer >> 8) & 0xff) / 255
            alpha = CGFloat(integer & 0xff) / 255
        } else {
            red = CGFloat((integer >> 16) & 0xff) / 255
            green = CGFloat((integer >> 8) & 0xff) / 255
            blue = CGFloat(integer & 0xff) / 255
            alpha = 1
        }

        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var relativeLuminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    func mixed(with other: NSColor, fraction: CGFloat) -> NSColor {
        guard
            let first = usingColorSpace(.sRGB),
            let second = other.usingColorSpace(.sRGB)
        else {
            return self
        }

        let clamped = min(max(fraction, 0), 1)
        return NSColor(
            srgbRed: first.redComponent + (second.redComponent - first.redComponent) * clamped,
            green: first.greenComponent + (second.greenComponent - first.greenComponent) * clamped,
            blue: first.blueComponent + (second.blueComponent - first.blueComponent) * clamped,
            alpha: first.alphaComponent + (second.alphaComponent - first.alphaComponent) * clamped
        )
    }
}
