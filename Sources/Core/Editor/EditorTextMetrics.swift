import Foundation

struct EditorCursorPosition: Equatable {
    let line: Int
    let column: Int
}

struct EditorLineIndex {
    private let textLength: Int
    private let lineStarts: [Int]

    init(text: String) {
        let nsText = text as NSString
        textLength = nsText.length

        var starts = [0]
        var searchLocation = 0
        while searchLocation < nsText.length {
            let range = nsText.range(
                of: "\n",
                options: [],
                range: NSRange(location: searchLocation, length: nsText.length - searchLocation)
            )
            guard range.location != NSNotFound else { break }
            searchLocation = range.location + range.length
            starts.append(searchLocation)
        }
        lineStarts = starts
    }

    func cursorPosition(for location: Int) -> EditorCursorPosition {
        let safeLocation = min(max(location, 0), textLength)
        let lineIndex = lineIndex(containing: safeLocation)
        return EditorCursorPosition(
            line: lineIndex + 1,
            column: safeLocation - lineStarts[lineIndex] + 1
        )
    }

    private func lineIndex(containing location: Int) -> Int {
        var lower = 0
        var upper = lineStarts.count - 1

        while lower <= upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= location {
                lower = middle + 1
            } else {
                upper = middle - 1
            }
        }

        return max(0, upper)
    }
}

