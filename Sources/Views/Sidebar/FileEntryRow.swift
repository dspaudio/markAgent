import SwiftUI

struct FileEntryRow: View {
    let entry: FileEntry
    let isSelected: Bool
    var depth = 0
    var isExpanded = false
    var isLoading = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: disclosureIconName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .opacity(entry.isDirectory ? 1 : 0)

            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let secondaryText = secondaryText {
                    Text(secondaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 8)
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 5)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if depth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<depth, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .padding(.leading, 14)
                            .padding(.trailing, 13)
                    }
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var disclosureIconName: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }
    
    private var iconName: String {
        switch entry.kind {
        case .directory: return "folder.fill"
        case .markdown: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
    
    private var iconColor: Color {
        switch entry.kind {
        case .directory: return .accentColor
        case .markdown: return .primary
        case .image: return .purple
        case .file: return .secondary
        }
    }
    
    private var secondaryText: String? {
        var parts: [String] = [kindText]
        
        if let size = entry.sizeBytes, !entry.isDirectory {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            parts.append(formatter.string(fromByteCount: size))
        }
        
        if let date = entry.modifiedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parts.append(formatter.string(from: date))
        }
        
        if parts.isEmpty { return nil }
        return parts.joined(separator: " • ")
    }

    private var kindText: String {
        switch entry.kind {
        case .directory: return String(localized: "폴더")
        case .markdown: return String(localized: "Markdown 파일")
        case .image: return String(localized: "이미지 파일")
        case .file: return String(localized: "파일")
        }
    }
}
