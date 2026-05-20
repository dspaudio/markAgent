import SwiftUI

struct FileBrowserSidebar: View {
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenMarkdown: (URL) -> Void
    var onOpenOtherFile: (URL) -> Void
    
    @State private var selectedEntryID: String?
    @State private var expandedDirectoryIDs: Set<String> = []
    @State private var expandedDirectoryEntries: [String: [FileEntry]] = [:]
    @State private var loadingDirectoryIDs: Set<String> = []
    @State private var directoryErrors: [String: String] = [:]
    @State private var previewImage: SidebarImageSelection?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scanner.currentDirectory.lastPathComponent)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button(action: {
                    scanner.goUp()
                }) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(scanner.currentDirectory.path == "/")
                .help("상위 폴더로 이동")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if scanner.isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .padding()
                    } else if let error = scanner.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding()
                    } else if scanner.entries.isEmpty {
                        Text("빈 폴더")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(displayRows) { row in
                            switch row {
                            case let .header(id: _, title: title, depth: depth):
                                sectionHeader(title, depth: depth)
                            case let .entry(entry, depth):
                                entryRow(entry, depth: depth)
                            case let .status(id: _, message: message, depth: depth, isError: isError):
                                statusRow(message, depth: depth, isError: isError)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            ScrollView {
                RecentDocumentsSection(
                    store: recentStore,
                    currentFileURL: currentFileURL,
                    onOpen: { url in
                        onOpenMarkdown(url)
                    }
                )
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(appColors?.panel ?? Color(NSColor.controlBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .sheet(item: $previewImage) { selection in
            SidebarImageViewer(url: selection.url)
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var directoryEntries: [FileEntry] {
        scanner.entries.filter(\.isDirectory)
    }

    private var fileEntries: [FileEntry] {
        scanner.entries.filter { !$0.isDirectory }
    }

    private var displayRows: [SidebarDisplayRow] {
        var rows: [SidebarDisplayRow] = []

        if !directoryEntries.isEmpty {
            rows.append(.header(id: "root-folders", title: "폴더", depth: 0))
            for entry in directoryEntries {
                appendDirectoryRows(for: entry, depth: 0, rows: &rows)
            }
        }

        if !fileEntries.isEmpty {
            rows.append(.header(id: "root-files", title: "파일", depth: 0))
            rows.append(contentsOf: fileEntries.map { .entry($0, depth: 0) })
        }

        return rows
    }

    private func appendDirectoryRows(for entry: FileEntry, depth: Int, rows: inout [SidebarDisplayRow]) {
        rows.append(.entry(entry, depth: depth))

        guard expandedDirectoryIDs.contains(entry.id) else { return }

        if loadingDirectoryIDs.contains(entry.id) {
            rows.append(.status(
                id: "\(entry.id)-loading",
                message: "불러오는 중...",
                depth: depth + 1,
                isError: false
            ))
            return
        }

        if let error = directoryErrors[entry.id] {
            rows.append(.status(
                id: "\(entry.id)-error",
                message: error,
                depth: depth + 1,
                isError: true
            ))
            return
        }

        let children = expandedDirectoryEntries[entry.id] ?? []
        if children.isEmpty {
            rows.append(.status(
                id: "\(entry.id)-empty",
                message: "빈 폴더",
                depth: depth + 1,
                isError: false
            ))
            return
        }

        let childDirectories = children.filter(\.isDirectory)
        let childFiles = children.filter { !$0.isDirectory }

        if !childDirectories.isEmpty {
            rows.append(.header(id: "\(entry.id)-folders", title: "폴더", depth: depth + 1))
            for child in childDirectories {
                appendDirectoryRows(for: child, depth: depth + 1, rows: &rows)
            }
        }

        if !childFiles.isEmpty {
            rows.append(.header(id: "\(entry.id)-files", title: "파일", depth: depth + 1))
            rows.append(contentsOf: childFiles.map { .entry($0, depth: depth + 1) })
        }
    }

    private func sectionHeader(_ title: String, depth: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private func statusRow(_ message: String, depth: Int, isError: Bool) -> some View {
        HStack {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(isError ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func entryRow(_ entry: FileEntry, depth: Int) -> some View {
        let isSelected = selectedEntryID == entry.id || currentFileURL?.path == entry.url.path

        FileEntryRow(entry: entry, isSelected: isSelected, depth: depth)
            .onTapGesture {
                handleSingleClick(entry)
            }
            .onTapGesture(count: 2) {
                handleDoubleClick(entry)
            }
    }

    private func handleSingleClick(_ entry: FileEntry) {
        selectedEntryID = entry.id

        if entry.isDirectory {
            toggleExpandedDirectory(entry)
        }
    }

    private func toggleExpandedDirectory(_ entry: FileEntry) {
        if expandedDirectoryIDs.contains(entry.id) {
            expandedDirectoryIDs.remove(entry.id)
            return
        }

        expandedDirectoryIDs.insert(entry.id)

        if expandedDirectoryEntries[entry.id] != nil || loadingDirectoryIDs.contains(entry.id) {
            return
        }

        loadExpandedDirectory(entry)
    }

    private func loadExpandedDirectory(_ entry: FileEntry) {
        loadingDirectoryIDs.insert(entry.id)
        directoryErrors[entry.id] = nil

        Task { [entry] in
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try DirectoryScanner.scan(directory: entry.url)
                }.value

                guard !Task.isCancelled else { return }
                expandedDirectoryEntries[entry.id] = entries
                loadingDirectoryIDs.remove(entry.id)
            } catch {
                guard !Task.isCancelled else { return }
                expandedDirectoryEntries[entry.id] = []
                directoryErrors[entry.id] = error.localizedDescription
                loadingDirectoryIDs.remove(entry.id)
            }
        }
    }
    
    private func handleDoubleClick(_ entry: FileEntry) {
        switch entry.kind {
        case .directory:
            break
        case .markdown:
            onOpenMarkdown(entry.url)
        case .image:
            previewImage = SidebarImageSelection(url: entry.url)
        case .file:
            onOpenOtherFile(entry.url)
        }
    }
}

private enum SidebarDisplayRow: Identifiable {
    case header(id: String, title: String, depth: Int)
    case entry(FileEntry, depth: Int)
    case status(id: String, message: String, depth: Int, isError: Bool)

    var id: String {
        switch self {
        case let .header(id, _, _):
            return id
        case let .entry(entry, depth):
            return "\(entry.id)-\(depth)"
        case let .status(id, _, _, _):
            return id
        }
    }
}

private struct SidebarImageSelection: Identifiable {
    let url: URL

    var id: String { url.path }
}

private struct SidebarImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            image = NSImage(contentsOf: url)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("닫기", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 1400, maxHeight: 1000)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.red)
                Text("이미지를 열 수 없습니다.")
                    .font(.headline)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
