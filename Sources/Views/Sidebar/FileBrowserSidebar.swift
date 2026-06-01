import SwiftUI

struct FileBrowserSidebar: View {
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenMarkdown: (URL) -> Void
    var onOpenOtherFile: (URL) -> Void
    var width: Double = 260
    
    @AppStorage("isOneClickPreviewEnabled") private var isOneClickPreviewEnabled = true
    @State private var selectedEntryID: String?
    @State private var expandedDirectoryIDs: Set<String> = []
    @State private var expandedDirectoryEntries: [String: [FileEntry]] = [:]
    @State private var loadingDirectoryIDs: Set<String> = []
    @State private var directoryErrors: [String: String] = [:]
    @State private var previewImage: SidebarImageSelection?
    @State private var previewState: SidebarPreviewState?
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
                .help(String(localized: "상위 폴더로 이동"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            
            Divider()
            
            if isOneClickPreviewEnabled, let previewState {
                sidebarPreview(previewState)
                    .frame(maxHeight: .infinity)
            } else {
                sidebarBrowser
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(appColors?.panel ?? Color(NSColor.controlBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .sheet(item: $previewImage) { selection in
            SidebarImageViewer(url: selection.url)
        }
        .onChange(of: isOneClickPreviewEnabled) { _, isEnabled in
            if !isEnabled {
                closePreview()
            }
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
            rows.append(.header(id: "root-folders", title: String(localized: "폴더"), depth: 0))
            for entry in directoryEntries {
                appendDirectoryRows(for: entry, depth: 0, rows: &rows)
            }
        }

        if !fileEntries.isEmpty {
            rows.append(.header(id: "root-files", title: String(localized: "파일"), depth: 0))
            rows.append(contentsOf: fileEntries.map { .entry($0, depth: 0) })
        }

        return rows
    }

    private var sidebarBrowser: some View {
        VStack(spacing: 0) {
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
    }

    private func appendDirectoryRows(for entry: FileEntry, depth: Int, rows: inout [SidebarDisplayRow]) {
        rows.append(.entry(entry, depth: depth))

        guard expandedDirectoryIDs.contains(entry.id) else { return }

        if loadingDirectoryIDs.contains(entry.id) {
            rows.append(.status(
                id: "\(entry.id)-loading",
                message: String(localized: "불러오는 중..."),
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
                message: String(localized: "빈 폴더"),
                depth: depth + 1,
                isError: false
            ))
            return
        }

        let childDirectories = children.filter(\.isDirectory)
        let childFiles = children.filter { !$0.isDirectory }

        if !childDirectories.isEmpty {
            rows.append(.header(id: "\(entry.id)-folders", title: String(localized: "폴더"), depth: depth + 1))
            for child in childDirectories {
                appendDirectoryRows(for: child, depth: depth + 1, rows: &rows)
            }
        }

        if !childFiles.isEmpty {
            rows.append(.header(id: "\(entry.id)-files", title: String(localized: "파일"), depth: depth + 1))
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
            previewState = nil
            toggleExpandedDirectory(entry)
        } else if isOneClickPreviewEnabled {
            loadPreview(for: entry)
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

    @ViewBuilder
    private func sidebarPreview(_ state: SidebarPreviewState) -> some View {
        FocusedEscapeContainer(onEscape: closePreview) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        closePreview()
                    } label: {
                        Label(String(localized: "미리보기 닫기"), systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "미리보기 닫기"))

                    Image(systemName: previewIconName(for: state.entry.kind))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(String(localized: "미리보기"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        openPreviewInTab(state.entry)
                    } label: {
                        Label(String(localized: "편집"), systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "탭에서 편집"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Group {
                    switch state.content {
                    case .loading:
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .markdown(let source):
                        ScrollView {
                            renderMarkdown(source, baseURL: state.entry.url.deletingLastPathComponent())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    case .text(let source):
                        ScrollView([.vertical, .horizontal]) {
                            Text(source)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    case .image(let image):
                        GeometryReader { geometry in
                            ScrollView([.vertical, .horizontal]) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        maxWidth: max(geometry.size.width - 20, 120),
                                        maxHeight: max(geometry.size.height - 20, 120)
                                    )
                                    .padding(10)
                            }
                        }
                    case .message(let message):
                        VStack(spacing: 8) {
                            Image(systemName: "doc.badge.exclamationmark")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            }
        }
    }

    private func previewIconName(for kind: FileEntry.Kind) -> String {
        switch kind {
        case .directory: return "folder.fill"
        case .markdown: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private func openPreviewInTab(_ entry: FileEntry) {
        switch entry.kind {
        case .directory:
            break
        case .markdown:
            onOpenMarkdown(entry.url)
        case .image, .file:
            onOpenOtherFile(entry.url)
        }
    }

    private func closePreview() {
        previewState = nil
        selectedEntryID = nil
    }

    private func loadPreview(for entry: FileEntry) {
        previewState = SidebarPreviewState(entry: entry, content: .loading)

        if entry.isImage {
            if let image = NSImage(contentsOf: entry.url) {
                previewState = SidebarPreviewState(entry: entry, content: .image(image))
            } else {
                previewState = SidebarPreviewState(entry: entry, content: .message(String(localized: "이미지를 열 수 없습니다.")))
            }
            return
        }

        Task { [entry] in
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try String(contentsOf: entry.url, encoding: .utf8)
                }.value

                guard !Task.isCancelled, selectedEntryID == entry.id else { return }
                previewState = SidebarPreviewState(
                    entry: entry,
                    content: entry.isMarkdown ? .markdown(source) : .text(source)
                )
            } catch {
                guard !Task.isCancelled, selectedEntryID == entry.id else { return }
                previewState = SidebarPreviewState(
                    entry: entry,
                    content: .message(String(format: String(localized: "파일을 읽을 수 없습니다: %@"), error.localizedDescription))
                )
            }
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

private struct SidebarPreviewState: Identifiable {
    let entry: FileEntry
    let content: SidebarPreviewContent

    var id: String { entry.id }
}

private enum SidebarPreviewContent {
    case loading
    case markdown(String)
    case text(String)
    case image(NSImage)
    case message(String)
}

private struct FocusedEscapeContainer<Content: View>: NSViewRepresentable {
    let onEscape: () -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> FocusedEscapeHostingView<Content> {
        let view = FocusedEscapeHostingView(rootView: content())
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: FocusedEscapeHostingView<Content>, context: Context) {
        nsView.rootView = content()
        nsView.onEscape = onEscape
    }
}

private final class FocusedEscapeHostingView<Content: View>: NSHostingView<Content> {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
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
