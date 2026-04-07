import Foundation

struct Template: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let content: String
    let variables: [TemplateVariable]
}

struct TemplateVariable: Codable, Sendable {
    let name: String
    let placeholder: String
    let defaultValue: String
    let description: String
}
