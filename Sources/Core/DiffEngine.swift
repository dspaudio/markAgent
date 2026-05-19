import Foundation

enum DiffLineType {
    case unchanged
    case added
    case removed
}

struct DiffLine {
    let type: DiffLineType
    let content: String
    let lineNumber: Int?     // new 파일 줄 번호 (removed이면 nil)
    let oldLineNumber: Int?  // old 파일 줄 번호 (added이면 nil)
}

struct DiffResult {
    let lines: [DiffLine]
    let addedCount: Int
    let removedCount: Int

    var isEmpty: Bool { addedCount == 0 && removedCount == 0 }
}

enum DiffEngine {
    /// 줄 단위 diff 계산. old가 빈 문자열(첫 로드)이면 빈 DiffResult 반환.
    nonisolated static func compute(
        old: String,
        new: String,
        emptyOldIsAllAdded: Bool = false
    ) -> DiffResult {
        guard !old.isEmpty || emptyOldIsAllAdded else {
            return DiffResult(lines: [], addedCount: 0, removedCount: 0)
        }

        if old.isEmpty {
            let addedLines = new.components(separatedBy: "\n").enumerated().map { index, line in
                DiffLine(type: .added, content: line, lineNumber: index + 1, oldLineNumber: nil)
            }
            return DiffResult(lines: addedLines, addedCount: addedLines.count, removedCount: 0)
        }

        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        let difference = newLines.difference(from: oldLines)

        var removedSet = Set<Int>()
        var insertedSet = Set<Int>()

        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removedSet.insert(offset)
            case .insert(let offset, _, _):
                insertedSet.insert(offset)
            }
        }

        var lines: [DiffLine] = []
        var addedCount = 0
        var removedCount = 0
        var oldIdx = 0
        var newIdx = 0
        var oldLineNum = 1
        var newLineNum = 1

        // 두 포인터 방식으로 순서를 유지하며 병합
        while oldIdx < oldLines.count || newIdx < newLines.count {
            if oldIdx < oldLines.count && removedSet.contains(oldIdx) {
                lines.append(DiffLine(
                    type: .removed,
                    content: oldLines[oldIdx],
                    lineNumber: nil,
                    oldLineNumber: oldLineNum
                ))
                removedCount += 1
                oldIdx += 1
                oldLineNum += 1
            } else if newIdx < newLines.count && insertedSet.contains(newIdx) {
                lines.append(DiffLine(
                    type: .added,
                    content: newLines[newIdx],
                    lineNumber: newLineNum,
                    oldLineNumber: nil
                ))
                addedCount += 1
                newIdx += 1
                newLineNum += 1
            } else if oldIdx < oldLines.count && newIdx < newLines.count {
                lines.append(DiffLine(
                    type: .unchanged,
                    content: newLines[newIdx],
                    lineNumber: newLineNum,
                    oldLineNumber: oldLineNum
                ))
                oldIdx += 1
                newIdx += 1
                oldLineNum += 1
                newLineNum += 1
            } else {
                break
            }
        }

        return DiffResult(lines: lines, addedCount: addedCount, removedCount: removedCount)
    }
}
