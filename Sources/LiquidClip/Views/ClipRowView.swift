import SwiftUI
import AppKit

public struct ClipRowView: View {
    public let item: ClipItem
    public let index: Int
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onPaste: () -> Void
    public let onTogglePin: () -> Void
    public let onDelete: () -> Void
    
    @State private var isHovered = false
    @ObservedObject private var settings = AppSettings.shared
    
    public init(
        item: ClipItem,
        index: Int,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.index = index
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onPaste = onPaste
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Index Shortcut Badge or Type Icon (Fixed 20pt width)
            ZStack {
                if settings.showShortcutsInList && index < 9 {
                    KeyboardBadge("\(index + 1)", isHighlighted: isSelected)
                } else {
                    Image(systemName: item.type.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(item.type.accentColor)
                }
            }
            .frame(width: 20)
            
            // Thumbnail / App Icon slot (Fixed 28x28 slot)
            ZStack {
                switch item.type {
                case .image:
                    if let img = item.loadPrimaryImage() {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    } else {
                        AppIconView(bundleId: item.sourceAppBundleId, size: 22)
                    }
                    
                case .color:
                    if let hex = item.colorHex {
                        let (r, g, b) = ClipItem.hexToRGB(hex)
                        Circle()
                            .fill(Color(red: Double(r)/255.0, green: Double(g)/255.0, blue: Double(b)/255.0))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.15), radius: 2)
                    }
                    
                case .file:
                    if item.isImageFile, let img = item.loadPrimaryImage() {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    } else if let first = item.filePaths?.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    } else {
                        AppIconView(bundleId: item.sourceAppBundleId, size: 22)
                    }
                    
                case .text, .url:
                    if let img = item.loadPrimaryImage() {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    } else {
                        AppIconView(bundleId: item.sourceAppBundleId, size: 22)
                    }
                }
            }
            .frame(width: 28, height: 28)
            
            // Content Info: Strictly 2 lines
            VStack(alignment: .leading, spacing: 2) {
                // Header line: Source App + Time + Badge
                HStack(spacing: 4) {
                    Text(item.sourceAppName ?? "剪贴板")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text(item.relativeTime)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Spacer(minLength: 4)
                    
                    // Pin indicator
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    
                    // Group Badge (if assigned)
                    if let group = StorageManager.shared.group(for: item.groupId) {
                        HStack(spacing: 2) {
                            Image(systemName: group.icon)
                                .font(.system(size: 7))
                            Text(group.name)
                                .font(.system(size: 8, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14))
                        .cornerRadius(3)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    // Type Badge
                    Text(item.badgeText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(3)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                // Content Title: Single line truncated
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            // Quick action buttons: fixed geometry with opacity transition (prevents layout jumping)
            HStack(spacing: 4) {
                Button(action: onPaste) {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("直接粘贴 (↵)")
                
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 11))
                        .foregroundColor(item.isPinned ? .orange : .secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "取消收藏" : "收藏项目")
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("删除此项 (⌫)")
            }
            .opacity((isHovered || isSelected) ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered || isSelected)
        }
        .frame(height: 50)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.4) : (isHovered ? Color.white.opacity(0.1) : Color.clear), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(action: onPaste) {
                Label("立即粘贴", systemImage: "arrow.right.doc.on.clipboard")
            }
            Button(action: onTogglePin) {
                Label(item.isPinned ? "取消收藏" : "收藏此项", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Menu("移动到分组") {
                ForEach(StorageManager.shared.groups) { group in
                    Button(action: {
                        StorageManager.shared.assignGroup(itemId: item.id, groupId: item.groupId == group.id ? nil : group.id)
                    }) {
                        HStack {
                            Text(group.name)
                            if item.groupId == group.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if item.groupId != nil {
                    Divider()
                    Button("从分组中移出") {
                        StorageManager.shared.assignGroup(itemId: item.id, groupId: nil)
                    }
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除此项", systemImage: "trash")
            }
        }
    }
}
