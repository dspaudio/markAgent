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
    @State private var loadPreviewTask: Task<Void, Never>? = nil
    @State private var searchText = ""
    @State private var searchMode: SidebarSearchMode = .files
    @State private var searchResults: [SidebarSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedSearchResultID: SidebarSearchResult.ID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    private let textPreviewByteLimit = 256 * 1024
    
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

            searchControls

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
        .onChange(of: searchText) { _, _ in
            scheduleSearch()
        }
        .onChange(of: searchMode) { _, _ in
            scheduleSearch()
        }
        .onChange(of: scanner.currentDirectory) { _, _ in
            clearSearchForDirectoryChange()
        }
        .onDisappear {
            searchTask?.cancel()
            loadPreviewTask?.cancel()
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

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            if isSearchActive {
                searchResultsList
            } else {
                fileBrowserList
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

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: searchMode == .grep ? "text.viewfinder" : "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                SidebarSearchField(
                    text: $searchText,
                    placeholder: searchMode == .grep ? String(localized: "내용 검색") : String(localized: "파일 검색"),
                    onSubmit: previewSelectedSearchCandidate,
                    onMoveSelection: moveSearchSelection,
                    onEscape: handleSearchEscape
                )
                    .frame(height: 17)
                    .accessibilityIdentifier("sidebar-search-field")

                if isSearchActive {
                    Button {
                        searchText = ""
                        resetSearchState()
                    } label: {
                        Label(String(localized: "검색 지우기"), systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "검색 지우기"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(appColors?.elevated ?? Color(nsColor: .textBackgroundColor).opacity(0.72))
            )

            Picker(String(localized: "검색 모드"), selection: $searchMode) {
                ForEach(SidebarSearchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("sidebar-search-mode")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var fileBrowserList: some View {
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
        .accessibilityIdentifier("sidebar-search-results-list")
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding()
                } else if let searchError {
                    statusRow(searchError, depth: 0, isError: true)
                        .padding(.top, 6)
                } else if searchResults.isEmpty {
                    statusRow(String(localized: "검색 결과 없음"), depth: 0, isError: false)
                        .padding(.top, 6)
                } else {
                    sectionHeader(String(localized: "검색 결과"), depth: 0)
                    ForEach(searchResults) { result in
                        searchResultRow(result)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
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

    @ViewBuilder
    private func searchResultRow(_ result: SidebarSearchResult) -> some View {
        let entry = result.entry
        let isSelected = selectedSearchResultID == result.id
            || selectedEntryID == entry.id
            || currentFileURL?.path == entry.url.path

        HStack(spacing: 8) {
            Image(systemName: previewIconName(for: entry.kind))
                .font(.system(size: 14))
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(result.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if result.detail != result.relativePath {
                    Text(result.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .onTapGesture {
            selectedSearchResultID = result.id
            handleSingleClick(entry)
        }
        .onTapGesture(count: 2) {
            selectedSearchResultID = result.id
            handleDoubleClick(entry)
        }
        .accessibilityIdentifier("sidebar-search-result-\(entry.name)")
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = searchText
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            selectedSearchResultID = nil
            return
        }

        let root = scanner.currentDirectory
        let mode = searchMode
        isSearching = true
        searchError = nil
        searchResults = []
        selectedSearchResultID = nil

        searchTask = Task { [query, root, mode] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                let results = try await SidebarFileSearch.search(root: root, query: query, mode: mode)
                guard !Task.isCancelled else { return }
                searchResults = results
                selectedSearchResultID = results.first?.id
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchError = error.localizedDescription
                isSearching = false
                selectedSearchResultID = nil
            }
        }
    }

    private func resetSearchState() {
        searchTask?.cancel()
        searchResults = []
        searchError = nil
        isSearching = false
        selectedSearchResultID = nil
    }

    private func previewSelectedSearchCandidate() {
        guard let entry = SidebarSearchNavigation.previewCandidate(
            from: searchResults,
            selectedResultID: selectedSearchResultID,
            isSearching: isSearching
        ) else { return }
        selectedEntryID = entry.id

        if entry.isDirectory {
            previewState = nil
            toggleExpandedDirectory(entry)
            return
        }

        loadPreview(for: entry)
    }

    private func moveSearchSelection(by offset: Int) {
        guard isSearchActive, !isSearching else { return }
        selectedSearchResultID = SidebarSearchNavigation.selectedResultID(
            afterMovingFrom: selectedSearchResultID,
            by: offset,
            in: searchResults
        )
    }

    private func handleSearchEscape() {
        var state = SidebarSearchStateSnapshot(
            text: searchText,
            results: searchResults,
            isSearching: isSearching,
            error: searchError,
            selectedResultID: selectedSearchResultID,
            isPreviewingResult: previewState != nil
        )

        let outcome = SidebarSearchStateReducer.applyEscape(to: &state)
        searchText = state.text
        searchResults = state.results
        isSearching = state.isSearching
        searchError = state.error
        selectedSearchResultID = state.selectedResultID

        switch outcome {
        case .none:
            break
        case .closePreview:
            closePreview()
        case .clearSearch:
            previewState = nil
        }
    }

    private func clearSearchForDirectoryChange() {
        searchTask?.cancel()
        var state = SidebarSearchStateSnapshot(
            text: searchText,
            results: searchResults,
            isSearching: isSearching,
            error: searchError,
            selectedResultID: selectedSearchResultID,
            isPreviewingResult: previewState != nil
        )
        SidebarSearchStateReducer.applyDirectoryChange(to: &state)
        searchText = state.text
        searchResults = state.results
        isSearching = state.isSearching
        searchError = state.error
        selectedSearchResultID = state.selectedResultID
        if !state.isPreviewingResult {
            previewState = nil
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

                        Text(relativePath(for: state.entry.url))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
                    case .image(let url):
                        GeometryReader { geometry in
                            ScrollView([.vertical, .horizontal]) {
                                LocalThumbnailImage(
                                    url: url,
                                    maxPixelSize: 720,
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
                .background(appColors?.elevated ?? Color(nsColor: .textBackgroundColor).opacity(0.72))
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

    private func relativePath(for url: URL) -> String {
        let rootPath = scanner.currentDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relativePath = String(filePath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.isEmpty ? url.lastPathComponent : relativePath
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
        loadPreviewTask?.cancel()
        loadPreviewTask = nil
        previewState = nil
        selectedEntryID = nil
    }

    private func loadPreview(for entry: FileEntry) {
        loadPreviewTask?.cancel()
        previewState = SidebarPreviewState(entry: entry, content: .loading)

        if entry.isImage {
            previewState = SidebarPreviewState(entry: entry, content: .image(entry.url))
            return
        }

        let byteLimit = textPreviewByteLimit
        loadPreviewTask = Task { [entry] in
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try loadTextPreview(from: entry.url, byteLimit: byteLimit)
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
    case image(URL)
    case message(String)
}

func loadTextPreview(from url: URL, byteLimit: Int) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
    if data.count <= byteLimit {
        return String(decoding: data, as: UTF8.self)
    }

    let prefix = data.prefix(byteLimit)
    return String(decoding: prefix, as: UTF8.self)
        + "\n\n..."
        + String(localized: "미리보기는 파일 앞부분만 표시합니다.")
}

private struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onMoveSelection: (Int) -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityIdentifier("sidebar-search-field")
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SidebarSearchField

        init(parent: SidebarSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveSelection(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveSelection(-1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

struct FocusedEscapeContainer<Content: View>: NSViewRepresentable {
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

final class FocusedEscapeHostingView<Content: View>: NSHostingView<Content> {
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
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
        ScrollView([.horizontal, .vertical]) {
            LocalThumbnailImage(
                url: url,
                maxPixelSize: 2400,
                maxWidth: 1400,
                maxHeight: 1000
            )
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
