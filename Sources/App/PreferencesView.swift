import AppKit
import GhosttyTheme
import SwiftUI

struct PreferencesView: View {
    @State private var preferences: GhosttyPreferences
    @State private var selectedThemeFilter: ThemeFilter
    @State private var saveErrorMessage: String?
    @State private var ripgrepStatus = RipgrepStatus.checking
    @State private var ripgrepInstallMessage: String?
    @State private var isInstallingRipgrep = false
    @AppStorage("isLeftSidebarVisible") private var isLeftSidebarVisible = true
    @AppStorage("isOneClickPreviewEnabled") private var isOneClickPreviewEnabled = true

    let onSaved: () -> Void

    private let themes = GhosttyThemeCatalog.allThemes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    private let fontSizes = stride(from: 10.0, through: 28.0, by: 0.5).map { $0 }
    private let codingFonts = FontCatalog.codingFonts()
    private let fallbackFonts = FontCatalog.allFonts()

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let initialPreferences = GhosttyConfig.preferences()
        let initialTheme = GhosttyThemeCatalog.theme(named: initialPreferences.themeName)
        _preferences = State(initialValue: initialPreferences)
        _selectedThemeFilter = State(initialValue: ThemeFilter(colorScheme: initialTheme?.previewColorScheme ?? .dark))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                settingsPane
                    .frame(width: 360)

                Divider()

                previewPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: preferences) { _, newValue in
            save(newValue)
        }
        .onAppear {
            refreshRipgrepStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Text(preferences.configURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var settingsPane: some View {
        Form {
            Section("Workspace") {
                Toggle("Show left sidebar by default", isOn: $isLeftSidebarVisible)
                Toggle("One click preview", isOn: $isOneClickPreviewEnabled)
            }

            Section("Search") {
                LabeledContent("ripgrep") {
                    ripgrepStatusView
                }

                Button(action: installRipgrep) {
                    Label("Install ripgrep", systemImage: "arrow.down.circle")
                }
                .disabled(!canInstallRipgrep)

                if let ripgrepInstallMessage {
                    Text(ripgrepInstallMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Terminal") {
                LabeledContent("Theme") {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(preferences.themeName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)

                        Text("Choose from preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Font Size", selection: $preferences.fontSize) {
                    ForEach(fontSizeOptions(including: preferences.fontSize), id: \.self) { size in
                        Text(fontSizeLabel(size)).tag(size)
                    }
                }
            }

            Section("Fonts") {
                Picker("Coding Font", selection: $preferences.primaryFontFamily) {
                    ForEach(fontOptions(codingFonts, including: preferences.primaryFontFamily), id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                Picker("Fallback Font", selection: $preferences.fallbackFontFamily) {
                    ForEach(fontOptions(fallbackFonts, including: preferences.fallbackFontFamily), id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Theme Preview")
                    .font(.headline)

                Text(preferences.themeName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }

            selectedThemeBanner

            themePreviewList
                .frame(height: 300)

            Text("Font Preview")
                .font(.headline)

            FontPreview(
                primaryFontFamily: preferences.primaryFontFamily,
                fallbackFontFamily: preferences.fallbackFontFamily,
                fontSize: preferences.fontSize,
                theme: selectedTheme
            )
            .frame(height: 150)

            Spacer()
        }
        .padding(24)
    }

    private var selectedThemeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white, Color.accentColor)

            Text("Selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(selectedTheme.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var themePreviewList: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                Picker("Theme Type", selection: $selectedThemeFilter) {
                    ForEach(ThemeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(filteredThemes) { theme in
                            Button {
                                preferences.themeName = theme.name
                            } label: {
                                ThemePreview(
                                    theme: theme,
                                    isSelected: theme.name == selectedTheme.name
                                )
                            }
                            .buttonStyle(.plain)
                            .id(theme.name)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 8)
                }
            }
            .onAppear {
                scrollToSelectedTheme(proxy)
            }
            .onChange(of: preferences.themeName) { _, _ in
                scrollToSelectedTheme(proxy)
            }
            .onChange(of: selectedThemeFilter) { _, _ in
                scrollToSelectedTheme(proxy)
            }
        }
    }

    private var selectedTheme: GhosttyThemeDefinition {
        GhosttyThemeCatalog.theme(named: preferences.themeName)
            ?? themes.first
            ?? GhosttyThemeDefinition(name: "Default", background: "1f1f1f", foreground: "d4d4d4")
    }

    private var filteredThemes: [GhosttyThemeDefinition] {
        themes.filter { ThemeFilter(colorScheme: $0.previewColorScheme) == selectedThemeFilter }
    }

    private var ripgrepStatusView: some View {
        HStack(spacing: 8) {
            switch ripgrepStatus {
            case .checking:
                ProgressView()
                    .scaleEffect(0.5)
                Text("Checking")
                    .foregroundStyle(.secondary)
            case .installed(let path):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .missing:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Not installed")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canInstallRipgrep: Bool {
        guard !isInstallingRipgrep else { return false }
        guard case .installed = ripgrepStatus else {
            return RipgrepTool.homebrewURL() != nil
        }
        return false
    }

    private func refreshRipgrepStatus() {
        if let executableURL = RipgrepTool.executableURL() {
            ripgrepStatus = .installed(executableURL.path)
        } else {
            ripgrepStatus = .missing
            if RipgrepTool.homebrewURL() == nil {
                ripgrepInstallMessage = String(localized: "Homebrew가 설치되어 있으면 ripgrep을 설치할 수 있습니다.")
            }
        }
    }

    private func installRipgrep() {
        isInstallingRipgrep = true
        ripgrepStatus = .checking
        ripgrepInstallMessage = String(localized: "ripgrep 설치 중...")

        Task {
            do {
                try await RipgrepTool.installWithHomebrew()
                ripgrepInstallMessage = String(localized: "ripgrep 설치가 완료되었습니다.")
            } catch {
                ripgrepInstallMessage = error.localizedDescription
            }
            isInstallingRipgrep = false
            refreshRipgrepStatus()
        }
    }

    private func scrollToSelectedTheme(_ proxy: ScrollViewProxy) {
        guard filteredThemes.contains(where: { $0.name == selectedTheme.name }) else { return }
        proxy.scrollTo(selectedTheme.name, anchor: .center)
    }

    private func save(_ preferences: GhosttyPreferences) {
        do {
            try GhosttyConfig.writePreferences(preferences)
            saveErrorMessage = nil
            onSaved()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func fontOptions(_ options: [String], including selected: String) -> [String] {
        guard !selected.isEmpty, !options.contains(selected) else { return options }
        return ([selected] + options).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func fontSizeOptions(including selected: Double) -> [Double] {
        guard !fontSizes.contains(selected) else { return fontSizes }
        return (fontSizes + [selected]).sorted()
    }

    private func fontSizeLabel(_ size: Double) -> String {
        size.rounded() == size ? "\(Int(size))" : String(format: "%.1f", size)
    }
}

private enum ThemeFilter: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            String(localized: "Light Themes")
        case .dark:
            String(localized: "Dark Themes")
        }
    }

    init(colorScheme: ColorScheme) {
        self = colorScheme == .light ? .light : .dark
    }
}

private enum RipgrepStatus: Equatable {
    case checking
    case installed(String)
    case missing
}

private struct ThemePreview: View {
    let theme: GhosttyThemeDefinition
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(theme.name)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Spacer()
                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(.white)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                } else {
                    Text(theme.background.hasPrefix("#") ? theme.background : "#\(theme.background)")
                        .font(.system(size: 12, design: .monospaced))
                        .opacity(0.72)
                }
            }

            HStack(spacing: 8) {
                ForEach(0 ..< 8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(theme.palette[index] ?? theme.foreground))
                        .frame(height: 26)
                }
            }

            Text("let agent = MarkAgent(theme: .\(theme.name.replacingOccurrences(of: " ", with: "")))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))

            Text("Markdown, terminals, and AI notes share one calm workspace.")
                .font(.system(size: 13, design: .monospaced))
                .opacity(0.78)
        }
        .foregroundStyle(color(theme.foreground))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(theme.background))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: isSelected ? Color.accentColor.opacity(0.28) : .clear, radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : color(theme.foreground).opacity(0.18), lineWidth: isSelected ? 3 : 1)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: NSColor.previewHex(hex) ?? .labelColor)
    }
}

private struct FontPreview: View {
    let primaryFontFamily: String
    let fallbackFontFamily: String
    let fontSize: Double
    let theme: GhosttyThemeDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(primaryFontFamily)
                .font(.system(size: 13, weight: .semibold))

            Text("func render(_ markdown: String) async throws -> View {\n    return try await terminal.preview(markdown)\n}")
                .font(.custom(primaryFontFamily, size: fontSize))
                .lineSpacing(3)

            Text(String(format: String(localized: "Fallback: %@ · 한글 미리보기 123"), fallbackFontFamily))
                .font(.custom(fallbackFontFamily, size: max(12, fontSize - 1)))
                .opacity(0.78)
        }
        .foregroundStyle(Color(nsColor: NSColor.previewHex(theme.foreground) ?? .labelColor))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: NSColor.previewHex(theme.background) ?? .textBackgroundColor).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension GhosttyThemeDefinition {
    var previewColorScheme: ColorScheme {
        guard let color = NSColor.previewHex(background) else { return .dark }
        return color.relativeLuminance < 0.5 ? .dark : .light
    }
}

private enum FontCatalog {
    static func codingFonts() -> [String] {
        let common = [
            "SF Mono",
            "Menlo",
            "Monaco",
            "JetBrains Mono",
            "Fira Code",
            "Cascadia Code",
            "Hack",
            "Source Code Pro",
            "IBM Plex Mono",
            "Roboto Mono",
            "Iosevka",
        ]
        let fixedPitchFamilies = allFonts().filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
        }
        return Array(Set(common + fixedPitchFamilies)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func allFonts() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

private extension NSColor {
    static func previewHex(_ string: String) -> NSColor? {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let integer = UInt64(value, radix: 16) else {
            return nil
        }

        return NSColor(
            srgbRed: CGFloat((integer >> 16) & 0xff) / 255,
            green: CGFloat((integer >> 8) & 0xff) / 255,
            blue: CGFloat(integer & 0xff) / 255,
            alpha: 1
        )
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
}
