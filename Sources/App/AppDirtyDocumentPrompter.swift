import AppKit

@MainActor
final class AppDirtyDocumentPrompter: DirtyDocumentPrompting {
    weak var window: NSWindow?

    init(window: NSWindow?) {
        self.window = window
    }

    func confirmCloseDirtyDocument(
        title: String,
        saveAction: @escaping () throws -> Void
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "저장되지 않은 변경사항이 있습니다."
        alert.informativeText = "\(title)에 저장되지 않은 변경사항이 있습니다. 저장하시겠습니까?"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning

        let response = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: alert.runModal())
            }
        }

        switch response {
        case .alertFirstButtonReturn:
            do {
                try saveAction()
                return true
            } catch {
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
