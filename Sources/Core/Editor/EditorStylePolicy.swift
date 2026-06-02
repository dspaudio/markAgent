import Foundation

enum EditorStyleMode: Equatable {
    case raw
    case renderedMarkdown
}

struct EditorStylePolicy: Equatable {
    private(set) var mode: EditorStyleMode
    private(set) var colorSignature: String

    init(mode: EditorStyleMode, colorSignature: String = "") {
        self.mode = mode
        self.colorSignature = colorSignature
    }

    mutating func shouldApplyFullStyle(mode newMode: EditorStyleMode, colorSignature newColorSignature: String) -> Bool {
        defer {
            mode = newMode
            colorSignature = newColorSignature
        }

        return mode != newMode || colorSignature != newColorSignature
    }

    func shouldStyleLocalEdit() -> Bool {
        mode == .renderedMarkdown
    }
}

