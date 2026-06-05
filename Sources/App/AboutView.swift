import AppKit
import SwiftUI

struct AboutView: View {
    static let githubURLString = "https://github.com/dspaudio/markAgent"

    private let libraries: [OpenSourceLibrary] = [
        OpenSourceLibrary(
            name: "swift-markdown",
            role: "GitHub Flavored Markdown parsing",
            license: "Apache-2.0",
            author: "Apple Inc. and the Swift Project authors",
            details: "Used to parse Markdown and GFM into a Swift syntax tree.",
            url: "https://github.com/swiftlang/swift-markdown"
        ),
        OpenSourceLibrary(
            name: "swift-cmark",
            role: "CommonMark and GFM parsing engine used by swift-markdown",
            license: "BSD-style and MIT notices",
            author: "John MacFarlane, with derived components by Vicent Martí, GitHub, Public Software Group e. V., and Karl Dubost",
            details: "Used transitively by swift-markdown for CommonMark/GFM behavior.",
            url: "https://github.com/swiftlang/swift-cmark"
        ),
        OpenSourceLibrary(
            name: "HighlightSwift",
            role: "Markdown preview code block syntax highlighting",
            license: "MIT; includes highlight.js under BSD-3-Clause",
            author: "Stefan Britton; highlight.js by Ivan Sagalaev",
            details: "Used for syntax-highlighted code blocks in rendered Markdown previews.",
            url: "https://github.com/appstefan/HighlightSwift"
        ),
        OpenSourceLibrary(
            name: "libghostty-spm",
            role: "Embedded terminal surface and Ghostty integration",
            license: "MIT; bundles libghostty under its own MIT terms",
            author: "@Lakr233; wraps Ghostty's terminal emulator library",
            details: "Used to host the embedded terminal tab.",
            url: "https://github.com/Lakr233/libghostty-spm"
        ),
        OpenSourceLibrary(
            name: "MSDisplayLink",
            role: "Display refresh support used by libghostty-spm",
            license: "MIT",
            author: "Lakr Aream",
            details: "Used by the terminal integration for display refresh scheduling.",
            url: "https://github.com/Lakr233/MSDisplayLink"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .padding(.bottom, 22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(title: "GitHub") {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Self.githubURLString)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 16)

                            Button("Open Repository") {
                                open(Self.githubURLString)
                            }
                        }
                    }

                    section(title: String(localized: "Open Source Libraries")) {
                        VStack(spacing: 10) {
                            ForEach(libraries) { library in
                                LibraryRow(library: library)
                            }
                        }
                    }

                    section(title: String(localized: "License Notice")) {
                        VStack(alignment: .leading, spacing: 8) {
                            licenseLine(String(localized: "MarkAgent includes and links against the open source components listed above."))
                            licenseLine(String(localized: "Package versions are resolved by Swift Package Manager through Package.resolved."))
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

            VStack(spacing: 6) {
                Text("MarkAgent")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("The Professional GUI for your CLI AI Agents.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    private var appIcon: NSImage {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }

        return NSApplication.shared.applicationIconImage
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?) where version != build:
            return String(format: String(localized: "Version %@ (%@)"), version, build)
        case let (version?, _):
            return String(format: String(localized: "Version %@"), version)
        default:
            return String(format: String(localized: "Version %@"), "1.0.0")
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func licenseLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct LibraryRow: View {
    let library: OpenSourceLibrary
    @State private var isHoveringURL = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(library.name)
                    .font(.body.weight(.semibold))

                Spacer(minLength: 12)

                Text(library.license)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            Text(library.role)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(String(format: String(localized: "Original author: %@"), library.author))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(library.details)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Button {
                open(library.url)
            } label: {
                Text(library.url)
                    .font(.system(.caption, design: .monospaced))
                    .underline(isHoveringURL)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.link)
            .foregroundStyle(isHoveringURL ? Color.accentColor : Color.secondary)
            .help(Text("Open repository"))
            .onHover { hovering in
                isHoveringURL = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct OpenSourceLibrary: Identifiable {
    let name: String
    let role: String
    let license: String
    let author: String
    let details: String
    let url: String

    var id: String { name }
}
