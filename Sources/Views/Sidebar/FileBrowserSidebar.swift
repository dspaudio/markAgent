import SwiftUI

struct FileBrowserSidebar: View {
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenMarkdown: (URL) -> Void
    var onOpenOtherFile: (URL) -> Void
    var width: Double = 260
    var searchCommandCenter: SidebarSearchCommandCenter? = nil
    
    @AppStorage("isOneClickPreviewEnabled") private var isOneClickPreviewEnabled = true
    @AppStorage("sidebarShowsHiddenFiles") private var showsHiddenFiles = false
    @AppStorage("isSidebarRecentDocumentsCollapsed") private var isRecentDocumentsCollapsed = false
    @State private var selectedEntryID: String?
    @State private var expandedDirectoryIDs: Set<String> = []
    @State private var expandedDirectoryEntries: [String: [FileEntry]] = [:]
    @State private var loadingDirectoryIDs: Set<String> = []
    @State private var directoryErrors: [String: String] = [:]
    @State private var previewImage: SidebarImageSelection?
    @State private var previewState: SidebarPreviewState?
    @State private var loadPreviewTask: Task<Void, Never>? = nil
    @State private var searchText = ""
    @State private var submittedSearchText = ""
    @State private var searchMode: SidebarSearchMode = .files
    @State private var searchResults: [SidebarSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var selectedSearchResultID: SidebarSearchResult.ID?
    @State private var searchFocusRequestID: UUID?
    @State private var handledSearchRequestID: UUID?
    @State private var isSearchVisible = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    private let textPreviewByteLimit = 256 * 1024
    private let searchDebounceDelayNanoseconds: UInt64 = 350_000_000
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scanner.currentDirectory.lastPathComponent)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()

                Button(action: toggleSearchVisibility) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSearchVisible ? Color.accentColor : Color.secondary)
                .help(isSearchVisible ? String(localized: "검색 숨기기") : String(localized: "검색 표시"))
                .accessibilityIdentifier("sidebar-toggle-search")

                Button(action: refreshFileList) {
                    if scanner.isLoading {
                        ProgressView()
                            .scaleEffect(0.45)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help(String(localized: "새로고침"))
                .disabled(scanner.isLoading)
                .accessibilityIdentifier("sidebar-refresh-file-list")

                Button(action: {
                    showsHiddenFiles.toggle()
                }) {
                    Image(systemName: showsHiddenFiles ? "eye" : "eye.slash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showsHiddenFiles ? Color.accentColor : Color.secondary)
                .help(showsHiddenFiles ? String(localized: "숨김 파일 숨기기") : String(localized: "숨김 파일 표시"))
                
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

            if isSearchVisible {
                searchControls

                Divider()
            }
            
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
        .background(
            SidebarEscapeKeyMonitor(
                isActive: isSearchVisible || (isOneClickPreviewEnabled && previewState != nil),
                onEscape: handleSidebarEscape
            )
        )
        .sheet(item: $previewImage) { selection in
            SidebarImageViewer(url: selection.url)
        }
        .onChange(of: isOneClickPreviewEnabled) { _, isEnabled in
            if !isEnabled {
                closePreview()
            }
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearchForCurrentInput()
        }
        .onChange(of: searchMode) { _, _ in
            scheduleSearchForCurrentInput(delayNanoseconds: 80_000_000)
        }
        .onChange(of: showsHiddenFiles) { _, isEnabled in
            expandedDirectoryEntries = [:]
            directoryErrors = [:]
            loadingDirectoryIDs = []
            scanner.setIncludeHiddenFiles(isEnabled)
            scheduleSearchForCurrentInput(delayNanoseconds: 80_000_000)
        }
        .onChange(of: scanner.currentDirectory) { _, _ in
            clearSearchForDirectoryChange()
        }
        .onChange(of: searchCommandCenter?.request?.id) { _, _ in
            handleExternalSearchRequest()
        }
        .onAppear {
            scanner.setIncludeHiddenFiles(showsHiddenFiles)
            handleExternalSearchRequest()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchTask?.cancel()
            loadPreviewTask?.cancel()
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private func refreshFileList() {
        expandedDirectoryIDs = []
        expandedDirectoryEntries = [:]
        loadingDirectoryIDs = []
        directoryErrors = [:]
        closePreview()
        scanner.reload()

        if isSearchActive || hasSearchText {
            scheduleSearchForCurrentInput(delayNanoseconds: 80_000_000)
        }
    }

    private var directoryEntries: [FileEntry] {
        scanner.entries.filter(\.isDirectory)
    }

    private var fileEntries: [FileEntry] {
        scanner.entries.filter { !$0.isDirectory }
    }

    private var isSearchActive: Bool {
        isSearchVisible && (!submittedSearchText.isEmpty || hasSearchText)
    }

    private var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchSummaryText: String? {
        guard isSearchActive else { return nil }
        if isSearching { return String(localized: "검색 중") }
        if let searchError { return searchError }
        return String(format: String(localized: "%d개 결과"), searchResults.count)
    }

    private var displayRows: [SidebarDisplayRow] {
        var rows: [SidebarDisplayRow] = []

        for entry in scanner.entries {
            if entry.isDirectory {
                appendDirectoryRows(for: entry, depth: 0, rows: &rows)
            } else {
                rows.append(.entry(entry, depth: 0))
            }
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
                    isCollapsed: $isRecentDocumentsCollapsed,
                    onOpen: { url in
                        onOpenMarkdown(url)
                    }
                )
            }
            .frame(maxHeight: isRecentDocumentsCollapsed ? 40 : 200)
        }
    }

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(SidebarSearchMode.allCases) { mode in
                    searchModeButton(mode)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: searchMode == .grep ? "text.viewfinder" : "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                SidebarSearchField(
                    text: $searchText,
                    placeholder: searchMode == .grep ? String(localized: "내용 검색") : String(localized: "파일 검색"),
                    onSubmit: submitSearch,
                    onMoveSelection: moveSearchSelection,
                    onEscape: handleSearchEscape,
                    focusRequestID: searchFocusRequestID
                )
                    .frame(height: 17)
                    .accessibilityIdentifier("sidebar-search-field")

                if hasSearchText {
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

            if let searchSummaryText {
                HStack(spacing: 6) {
                    Circle()
                        .fill(searchError == nil ? Color.accentColor : Color.red)
                        .frame(width: 5, height: 5)
                    Text(searchSummaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(searchError == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier("sidebar-search-summary")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func searchModeButton(_ mode: SidebarSearchMode) -> some View {
        let isSelected = searchMode == mode
        return Button {
            isSearchVisible = true
            searchMode = mode
            requestSearchFocus()
        } label: {
            Label(mode.title, systemImage: mode == .grep ? "text.viewfinder" : "doc.viewfinder")
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.36) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("sidebar-search-mode-\(mode.rawValue)")
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

        for child in children {
            if child.isDirectory {
                appendDirectoryRows(for: child, depth: depth + 1, rows: &rows)
            } else {
                rows.append(.entry(child, depth: depth + 1))
            }
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

        FileEntryRow(
            entry: entry,
            isSelected: isSelected,
            depth: depth,
            isExpanded: expandedDirectoryIDs.contains(entry.id),
            isLoading: loadingDirectoryIDs.contains(entry.id)
        )
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

    private func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            resetSearchState()
            return
        }

        if query == submittedSearchText, !isSearching {
            previewSelectedSearchCandidate()
            return
        }

        searchDebounceTask?.cancel()
        startSearch(query: query)
    }

    private func scheduleSearchForCurrentInput(delayNanoseconds: UInt64? = nil) {
        searchDebounceTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            resetSearchState()
            return
        }

        if query != submittedSearchText {
            searchTask?.cancel()
            searchError = nil
            isSearching = true
            selectedSearchResultID = nil
        }

        let delay = delayNanoseconds ?? searchDebounceDelayNanoseconds
        searchDebounceTask = Task { [query, delay] in
            do {
                try await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                startSearch(query: query)
            } catch {
                return
            }
        }
    }

    private func startSearch(query: String) {
        searchDebounceTask?.cancel()
        searchTask?.cancel()

        let root = scanner.currentDirectory
        let mode = searchMode
        let includeHidden = showsHiddenFiles
        submittedSearchText = query
        isSearching = true
        searchError = nil
        searchResults = []
        selectedSearchResultID = nil

        searchTask = Task { [query, root, mode, includeHidden] in
            do {
                let results = try await SidebarFileSearch.search(
                    root: root,
                    query: query,
                    mode: mode,
                    includeHidden: includeHidden
                )
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
        searchDebounceTask?.cancel()
        searchTask?.cancel()
        submittedSearchText = ""
        searchResults = []
        searchError = nil
        isSearching = false
        selectedSearchResultID = nil
    }

    private func toggleSearchVisibility() {
        if isSearchVisible {
            closeSearch()
            return
        }

        isSearchVisible = true
        requestSearchFocus()
    }

    private func handleExternalSearchRequest() {
        guard let request = searchCommandCenter?.request else { return }
        guard handledSearchRequestID != request.id else { return }
        handledSearchRequestID = request.id
        isSearchVisible = true
        searchMode = request.mode
        closePreview()
        requestSearchFocus()
        scheduleSearchForCurrentInput(delayNanoseconds: 80_000_000)
    }

    private func requestSearchFocus() {
        searchFocusRequestID = UUID()
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
        stepBackFromSearch()
    }

    private func handleSidebarEscape() {
        if isSearchVisible {
            stepBackFromSearch()
            return
        }

        closePreview()
    }

    private func stepBackFromSearch() {
        if previewState != nil {
            closePreview()
            requestSearchFocus()
            return
        }

        if hasSearchText || !submittedSearchText.isEmpty || !searchResults.isEmpty || searchError != nil || isSearching {
            resetSearchState()
            searchText = ""
            requestSearchFocus()
            return
        }

        closeSearch()
    }

    private func closeSearch() {
        isSearchVisible = false
        resetSearchState()
        closePreview()
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
        submittedSearchText = state.text
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
        let includeHidden = showsHiddenFiles

        Task { [entry, includeHidden] in
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try DirectoryScanner.scan(directory: entry.url, includeHidden: includeHidden)
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
                            .contentShape(Rectangle())
                    }
                    .frame(width: 24, height: 36, alignment: .leading)
                    .background(alignment: .leading) {
                        Color.clear
                            .frame(width: 40, height: 36)
                            .contentShape(Rectangle())
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
                .padding(.vertical, 4)

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    case .text(let source):
                        ScrollView([.vertical, .horizontal]) {
                            SidebarSyntaxHighlightedText(source: source, fileURL: state.entry.url)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    case entry(FileEntry, depth: Int)
    case status(id: String, message: String, depth: Int, isError: Bool)

    var id: String {
        switch self {
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

private struct SidebarSyntaxHighlightedText: View {
    let source: String
    let fileURL: URL

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        Text(attributedSource)
            .font(.system(size: 11, design: .monospaced))
    }

    private var attributedSource: AttributedString {
        let appColors = terminalAppTheme?.theme(for: colorScheme)?.appColors()
        let attributed = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: appColors?.textForeground ?? NSColor.textColor
            ]
        )
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard let language = CodeHighlightLanguage(fileURL: fileURL) else {
            return (try? AttributedString(attributed, including: \.appKit)) ?? AttributedString(source)
        }

        let colors = SidebarSyntaxColors(appColors: appColors)
        apply(.keyword, color: colors.keyword, language: language, range: fullRange, to: attributed)
        apply(.number, color: colors.number, language: language, range: fullRange, to: attributed)
        if language.usesMarkupTags {
            apply(.tag, color: colors.tag, language: language, range: fullRange, to: attributed)
        }
        apply(.string, color: colors.string, language: language, range: fullRange, to: attributed)
        apply(.comment, color: colors.comment, language: language, range: fullRange, to: attributed)

        return (try? AttributedString(attributed, including: \.appKit)) ?? AttributedString(source)
    }

    private func apply(
        _ token: RawCodeSyntaxToken,
        color: NSColor,
        language: CodeHighlightLanguage,
        range: NSRange,
        to attributed: NSMutableAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: RawCodeSyntaxRules.pattern(for: token, language: language)) else {
            return
        }
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

private struct SidebarSyntaxColors {
    let comment: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let tag: NSColor

    init(appColors: TerminalAppColors?) {
        comment = appColors?.textForeground.withAlphaComponent(0.62) ?? NSColor.systemGray
        keyword = appColors?.syntaxMagenta ?? NSColor.systemPurple
        string = appColors?.syntaxGreen ?? NSColor.systemGreen
        number = appColors?.syntaxYellow ?? NSColor.systemOrange
        tag = appColors?.syntaxBlue ?? NSColor.systemBlue
    }
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
    var focusRequestID: UUID?

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
        if context.coordinator.handledFocusRequestID != focusRequestID {
            context.coordinator.handledFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SidebarSearchField
        var handledFocusRequestID: UUID?

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

private struct SidebarEscapeKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.update(isActive: isActive, onEscape: onEscape)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onEscape: onEscape)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var monitor: Any?
        private var onEscape: (() -> Void)?

        func update(isActive: Bool, onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
            if isActive {
                installMonitorIfNeeded()
            } else {
                removeMonitor()
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.onEscape?()
                return nil
            }
        }

        deinit {
            removeMonitor()
        }
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
