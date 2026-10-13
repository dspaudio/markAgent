#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import GhosttyKit

extension AppTerminalView {
    public var isMouseCaptured: Bool {
        guard let surface = surface?.rawValue else { return false }
        return ghostty_surface_mouse_captured(surface)
    }

    public func invalidateMousePosition(modifiers: NSEvent.ModifierFlags = []) {
        guard let surface = surface?.rawValue else { return }
        // 임베디드 엔진은 같은 좌표에서 수정키만 바뀐 이벤트를 무시한다.
        ghostty_surface_mouse_pos(surface, -1, -1, TerminalInputModifiers(from: modifiers).ghosttyMods)
    }

    public func updateMousePosition(at point: NSPoint, modifiers: NSEvent.ModifierFlags) {
        guard let surface = surface?.rawValue else { return }
        ghostty_surface_mouse_pos(
            surface, point.x, bounds.height - point.y,
            TerminalInputModifiers(from: modifiers).ghosttyMods
        )
    }

    public func setHoverQueryActive(_ active: Bool, modifiers: NSEvent.ModifierFlags) {
        guard let surface = surface?.rawValue else { return }
        // UNKNOWN 슬롯은 선택·붙여넣기·링크 클릭을 실행하지 않는다.
        // Shift 조회 중에만 예약하여 가상 이동이 TUI mouse report로 전달되지 않게 한다.
        _ = ghostty_surface_mouse_button(
            surface, active ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_UNKNOWN, TerminalInputModifiers(from: modifiers).ghosttyMods
        )
    }

    public func wordUnderPointer(at point: NSPoint) -> String? {
        guard let surface = surface?.rawValue else { return nil }
        func freeText(_ text: UnsafeMutablePointer<ghostty_text_s>) {
            // 고정 1.4.0 바이너리의 실제 free_text ABI는 첫 번째 인자를 text로 읽는다.
            ghostty_surface_free_text(UnsafeMutableRawPointer(text), text)
        }
        var word = ghostty_text_s()
        guard ghostty_surface_quicklook_word(surface, &word) else { return nil }
        defer { freeText(&word) }
        let size = ghostty_surface_size(surface)
        let scale = window?.backingScaleFactor ?? 1
        let cellWidth = CGFloat(size.cell_width_px) / scale
        let cellHeight = CGFloat(size.cell_height_px) / scale
        guard word.text_len > 0, cellWidth > 0, cellHeight > 0 else { return nil }
        let originSelection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0),
            rectangle: true
        )
        var origin = ghostty_text_s()
        guard ghostty_surface_read_text(surface, originSelection, &origin) else { return nil }
        defer { freeText(&origin) }
        let row = Int(((word.tl_px_y - origin.tl_px_y) / cellHeight).rounded())
        let column = Int(((point.x - origin.tl_px_x) / cellWidth).rounded(.down))
        guard (0..<Int(size.rows)).contains(row), (0..<Int(size.columns)).contains(column) else { return nil }
        func text(_ first: Int, _ last: Int) -> String? {
            let selection = ghostty_selection_s(
                top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                          x: UInt32(first), y: UInt32(row)),
                bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                              x: UInt32(last), y: UInt32(row)),
                rectangle: true
            )
            var result = ghostty_text_s()
            guard ghostty_surface_read_text(surface, selection, &result) else { return nil }
            defer { freeText(&result) }
            guard let bytes = result.text else { return "" }
            return String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(result.text_len)),
                          as: UTF8.self)
        }
        // native 단어 경계는 "설계.md"를 "설", "계", ".md"로 나눈다.
        // 셀 선택으로 포인터가 가리키는 문자를 찾은 뒤 공백 경계까지 읽는다.
        guard let cell = text(column, column),
              !cell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let line = text(0, Int(size.columns) - 1),
              let prefix = text(0, column), !prefix.isEmpty,
              let clicked = line.index(line.startIndex, offsetBy: prefix.count - 1, limitedBy: line.endIndex),
              clicked < line.endIndex, !line[clicked].isWhitespace else { return nil }
        let start = line[..<clicked].lastIndex(where: \.isWhitespace).map { line.index(after: $0) } ?? line.startIndex
        let end = line[clicked...].firstIndex(where: \.isWhitespace) ?? line.endIndex
        return String(line[start..<end])
    }

    public func hoverLinkRects(
        at point: NSPoint, matching: (NSPoint) -> Bool
    ) -> [NSRect] {
        guard let surface = surface?.rawValue else { return [] }
        let size = ghostty_surface_size(surface)
        let columns = Int(size.columns)
        let rows = Int(size.rows)
        guard columns > 0, rows > 0 else { return [] }
        // 고정 1.4.0 바이너리는 헤더의 두 번째 인자 대신 첫 번째 인자를 text로 읽는다.
        // 다른 시그니처로 캐스트하면 release 최적화가 첫 인자를 undef로 낮추므로
        // 선언된 C 호출을 유지하면서 실제 ABI가 읽는 첫 인자에도 text를 전달한다.
        func freeText(_ text: UnsafeMutablePointer<ghostty_text_s>) {
            ghostty_surface_free_text(UnsafeMutableRawPointer(text), text)
        }
        var word = ghostty_text_s()
        guard ghostty_surface_quicklook_word(surface, &word) else { return [] }
        defer { freeText(&word) }
        guard word.text_len > 0, word.tl_px_x >= 0, word.tl_px_y >= 0 else { return [] }
        let scale = window?.backingScaleFactor ?? 1
        let cellWidth = CGFloat(size.cell_width_px) / scale
        let cellHeight = CGFloat(size.cell_height_px) / scale
        guard cellWidth > 0, cellHeight > 0 else { return [] }
        let originSelection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0),
            rectangle: true
        )
        var origin = ghostty_text_s()
        guard ghostty_surface_read_text(surface, originSelection, &origin) else { return [] }
        defer { freeText(&origin) }
        // offset·열 수의 스냅샷 대신 실제 baseline과 padding 기준점으로 행·열을 구한다.
        let wordRow = Int(((word.tl_px_y - origin.tl_px_y) / cellHeight).rounded())
        let wordColumn = Int(((word.tl_px_x - origin.tl_px_x) / cellWidth).rounded())
        guard (0..<rows).contains(wordRow), (0..<columns).contains(wordColumn) else { return [] }
        let wordStart = wordRow * columns + wordColumn
        let wordEnd = min(wordStart + Int(word.offset_len), columns * rows - 1)
        let originX = origin.tl_px_x

        func cellPoint(_ column: Int, _ row: Int) -> NSPoint {
            NSPoint(x: originX + (CGFloat(column) + 0.5) * cellWidth,
                    y: bounds.maxY - word.tl_px_y - CGFloat(row - wordRow) * cellHeight)
        }

        func text(_ first: Int, _ last: Int, _ row: Int) -> String? {
            let selection = ghostty_selection_s(
                top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                          x: UInt32(first), y: UInt32(row)),
                bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                              x: UInt32(last), y: UInt32(row)),
                rectangle: true
            )
            var result = ghostty_text_s()
            guard ghostty_surface_read_text(surface, selection, &result) else { return nil }
            defer { freeText(&result) }
            guard let bytes = result.text else { return "" }
            return String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(result.text_len)),
                          as: UTF8.self)
        }

        func span(_ row: Int, _ column: Int) -> (first: Int, last: Int, rect: NSRect)? {
            guard matching(cellPoint(column, row)) else { return nil }
            var first = column
            var last = column
            while first > 0, matching(cellPoint(first - 1, row)) { first -= 1 }
            while last + 1 < columns, matching(cellPoint(last + 1, row)) { last += 1 }
            guard let raw = text(first, last, row) else { return nil }
            let visible = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visible.isEmpty else { return nil }

            // 셀 범위는 엔진에서 읽는다. UTF-8 길이로 CJK·emoji 폭을 추정하지 않는다.
            var lower = first
            var upper = last
            while lower < upper {
                let middle = (lower + upper) / 2
                guard let prefix = text(first, middle, row) else { return nil }
                if prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            first = lower
            lower = first
            upper = last
            while lower < upper {
                let middle = (lower + upper) / 2
                guard let prefix = text(first, middle, row) else { return nil }
                if prefix.trimmingCharacters(in: .whitespacesAndNewlines) == visible {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            // wide glyph의 두 번째 셀은 텍스트를 추가하지 않지만 밑줄 폭에는 포함한다.
            if lower < last, text(first, lower + 1, row) == text(first, lower, row) {
                lower += 1
            }
            last = lower
            return (first, last, NSRect(
                x: originX + CGFloat(first) * cellWidth,
                y: cellPoint(first, row).y - 2 / scale,
                width: CGFloat(last - first + 1) * cellWidth, height: 1 / scale
            ))
        }

        guard let seed = (wordStart...wordEnd).first(where: {
            matching(cellPoint($0 % columns, $0 / columns))
        }), let initial = span(seed / columns, seed % columns) else { return [] }
        if wordRow == wordEnd / columns,
           point.x < initial.rect.minX || point.x >= initial.rect.maxX { return [] }
        var rectangles = [initial.rect]
        var row = seed / columns
        var edge = initial.first
        while edge == 0, row > 0, let previous = span(row - 1, columns - 1),
              previous.last == columns - 1 {
            rectangles.insert(previous.rect, at: 0)
            row -= 1
            edge = previous.first
        }
        row = seed / columns
        edge = initial.last
        while edge == columns - 1, row + 1 < rows, let next = span(row + 1, 0),
              next.first == 0 {
            rectangles.append(next.rect)
            row += 1
            edge = next.last
        }
        return rectangles
    }
}
#endif
