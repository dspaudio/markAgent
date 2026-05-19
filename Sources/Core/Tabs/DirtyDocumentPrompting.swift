import Foundation

@MainActor
protocol DirtyDocumentPrompting: AnyObject {
    func confirmCloseDirtyDocument(
        title: String,
        saveAction: @escaping () throws -> Void
    ) async -> Bool
}
