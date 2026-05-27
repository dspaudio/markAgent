import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDirtyDocumentPrompter: DirtyDocumentPrompting {
    weak var window: NSWindow?

    init(window: NSWindow?) {
        self.window = window
    }

    func confirmCloseDirtyDocument(
        title: String,
        fileURL: URL?,
        saveAction: @escaping (URL?) throws -> Void
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "Do you want to save the changes you made to \"\(title)\"?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = await runAlert(alert)

        switch response {
        case .alertFirstButtonReturn:
            do {
                let saveURL = fileURL ?? chooseSaveURL(suggestedName: title)
                guard fileURL != nil || saveURL != nil else { return false }
                try saveAction(saveURL)
                return true
            } catch {
                showSaveError(error)
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func runAlert(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private func chooseSaveURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Markdown Document"
        panel.prompt = "Save"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "txt"),
            .plainText
        ].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could Not Save Document"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }
}
