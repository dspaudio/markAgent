import SwiftUI

struct FileEntryRow: View {
    let entry: FileEntry
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
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
        var parts: [String] = []
        
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
}
