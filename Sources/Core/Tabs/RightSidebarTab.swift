import Foundation

enum RightSidebarTab: String, CaseIterable, Identifiable {
    case snippets
    case timeline
    case gitHistory
    case fileBrowser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snippets:
            return String(localized: "스니펫")
        case .timeline:
            return String(localized: "타임라인")
        case .gitHistory:
            return String(localized: "Git 히스토리")
        case .fileBrowser:
            return String(localized: "파일 브라우저")
        }
    }

    var systemImage: String {
        switch self {
        case .snippets:
            return "text.quote"
        case .timeline:
            return "clock.arrow.circlepath"
        case .gitHistory:
            return "clock.arrow.circlepath"
        case .fileBrowser:
            return "folder"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .snippets:
            return "right-utility-snippets"
        case .timeline:
            return "right-utility-timeline"
        case .gitHistory:
            return "right-utility-git-history"
        case .fileBrowser:
            return "right-utility-file-browser"
        }
    }
}
