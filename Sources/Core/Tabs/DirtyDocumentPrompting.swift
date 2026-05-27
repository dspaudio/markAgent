import Foundation

@MainActor
protocol DirtyDocumentPrompting: AnyObject {
    func confirmCloseDirtyDocument(
        title: String,
        fileURL: URL?,
        saveAction: @escaping (URL?) throws -> Void
    ) async -> Bool
}
