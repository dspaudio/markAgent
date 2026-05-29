import AppKit
import Foundation
import SwiftUI

struct MarkdownImageReference: Equatable {
    let source: String
    let altText: String
    let title: String?
    let resolvedURL: URL?
    let displayPath: String
    let isMissing: Bool

    var canOpen: Bool { resolvedURL != nil && !isMissing }

    static func resolve(
        source: String,
        altText: String = "",
        title: String? = nil,
        baseURL: URL?
    ) -> MarkdownImageReference {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = resolvedURL(for: trimmedSource, baseURL: baseURL)
        let isMissing = url.map { $0.isFileURL && !FileManager.default.fileExists(atPath: $0.path) } ?? true
        return MarkdownImageReference(
            source: trimmedSource,
            altText: altText,
            title: title,
            resolvedURL: url,
            displayPath: url.map { $0.isFileURL ? $0.path : $0.absoluteString } ?? trimmedSource,
            isMissing: isMissing
        )
    }

    private static func resolvedURL(for source: String, baseURL: URL?) -> URL? {
        guard !source.isEmpty else { return nil }
        if let remoteURL = URL(string: source), remoteURL.scheme == "http" || remoteURL.scheme == "https" {
            return remoteURL
        }
        if source.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: source).expandingTildeInPath)
        }
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }
        guard let baseURL else { return URL(fileURLWithPath: source) }
        return baseURL.appendingPathComponent(source).standardizedFileURL
    }
}

struct MarkdownImagePreview: View {
    let reference: MarkdownImageReference
    var compact = false

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            imageSurface
                .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                    hoverPreview
                }

            if reference.isMissing {
                Label(String(format: String(localized: "이미지를 찾을 수 없습니다: %@"), reference.displayPath), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !compact {
                HStack(spacing: 8) {
                    Text(reference.altText.isEmpty ? reference.source : reference.altText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        openImage()
                    } label: {
                        Label("열기", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!reference.canOpen)
                }
            }
        }
    }

    @ViewBuilder
    private var imageSurface: some View {
        if reference.isMissing {
            missingSurface
        } else if let url = reference.resolvedURL, url.isFileURL, let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: compact ? 180 : 720, maxHeight: compact ? 120 : 420, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovering in isHovering = hovering }
                .onTapGesture(perform: openImage)
                .help(String(localized: "클릭해서 이미지 열기"))
        } else if let url = reference.resolvedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    missingSurface
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: compact ? 180 : 720, maxHeight: compact ? 120 : 420, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in isHovering = hovering }
            .onTapGesture(perform: openImage)
            .help(String(localized: "클릭해서 이미지 열기"))
        } else {
            missingSurface
        }
    }

    private var missingSurface: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(reference.altText.isEmpty ? String(localized: "깨진 이미지") : reference.altText)
                    .font(.callout.weight(.medium))
                Text(reference.displayPath)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.red.opacity(0.35)))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var hoverPreview: some View {
        if let url = reference.resolvedURL, !reference.isMissing, url.isFileURL, let nsImage = NSImage(contentsOf: url) {
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 900, maxHeight: 640)
                Text(reference.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(10)
        }
    }

    private func openImage() {
        guard let url = reference.resolvedURL, !reference.isMissing else { return }
        NSWorkspace.shared.open(url)
    }
}

enum MarkdownImageLineParser {
    static func firstImage(in line: String, baseURL: URL?) -> MarkdownImageReference? {
        let pattern = #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let sourceRange = Range(match.range(at: 2), in: line)
        else { return nil }

        let altText = Range(match.range(at: 1), in: line).map { String(line[$0]) } ?? ""
        let title = Range(match.range(at: 3), in: line).map { String(line[$0]) }
        return MarkdownImageReference.resolve(
            source: String(line[sourceRange]),
            altText: altText,
            title: title,
            baseURL: baseURL
        )
    }
}
