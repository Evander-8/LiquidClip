/**
 * [INPUT]: 依赖 ClipItem、StorageManager、ClipboardMonitor、SoundManager 与 Views/Inspectors 下的分类型检查器
 * [OUTPUT]: 提供右侧内容检查器路由容器 ClipDetailView，负责顶部动作栏、分组归档与按类型分发渲染
 * [POS]: 右侧详情检查器主入口，连接 MainWindowView 与各类型 Inspector 子视图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct ClipDetailView: View {
    public let item: ClipItem?
    public let onPaste: () -> Void
    public let onPastePlainText: (() -> Void)?
    public let onCopy: () -> Void
    public let onTogglePin: () -> Void
    public let onDelete: () -> Void
    public var onShowToast: ((String) -> Void)?
    
    @State private var showFullText: Bool = false
    
    public init(
        item: ClipItem?,
        onPaste: @escaping () -> Void,
        onPastePlainText: (() -> Void)? = nil,
        onCopy: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onShowToast: ((String) -> Void)? = nil
    ) {
        self.item = item
        self.onPaste = onPaste
        self.onPastePlainText = onPastePlainText
        self.onCopy = onCopy
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onShowToast = onShowToast
    }
    
    public var body: some View {
        Group {
            if let item = item {
                VStack(spacing: 0) {
                    // Top Action Bar
                    HStack(spacing: 6) {
                        Button(action: onPaste) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("粘贴")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                KeyboardBadge("↵", onAccent: true)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .layoutPriority(2)
                        
                        if let onPastePlainText = onPastePlainText,
                           item.type == .text || item.type == .url || item.type == .color {
                            Button(action: onPastePlainText) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.plaintext")
                                        .font(.system(size: 11))
                                    Text("纯文本")
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help("纯文本粘贴（忽略富文本样式，快捷键 ⇧↵）")
                        }
                        
                        Button(action: onCopy) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                Text("复制")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .layoutPriority(1)
                        
                        // Group assignment menu
                        Menu {
                            Section("分组归档 (防删除保护)") {
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
                            }
                            if item.groupId != nil {
                                Divider()
                                Button("移出当前分组") {
                                    StorageManager.shared.assignGroup(itemId: item.id, groupId: nil)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: item.groupId != nil ? "folder.fill" : "folder.badge.plus")
                                    .font(.system(size: 11))
                                if let g = StorageManager.shared.group(for: item.groupId) {
                                    Text(g.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: 90, alignment: .leading)
                                } else {
                                    Text("分组")
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                }
                            }
                            .foregroundColor(item.groupId != nil ? .accentColor : .primary)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(item.groupId != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            .cornerRadius(8)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("将记录加入自定义分组 (分组内容不会被自动清理或清空)")
                        
                        Spacer()
                        
                        Button(action: onTogglePin) {
                            Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                                .font(.system(size: 12))
                                .foregroundColor(item.isPinned ? .orange : .secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "取消收藏" : "收藏")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("删除")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.03))
                    
                    Divider().opacity(0.4)
                    
                    // Selected Item Header Info
                    HStack(spacing: 8) {
                        AppIconView(bundleId: item.sourceAppBundleId, size: 15)
                        Text(item.sourceAppName ?? "剪贴板")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(item.relativeTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if let group = StorageManager.shared.group(for: item.groupId) {
                            HStack(spacing: 3) {
                                Image(systemName: group.icon)
                                    .font(.system(size: 8))
                                Text(group.name)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                        }
                        
                        Text(item.badgeText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    
                    // Route to modular Type Inspector
                    switch item.type {
                    case .text:
                        TextInspectorView(item: item, showFullText: $showFullText, onCopyText: copyTransformedText)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .image:
                        ScrollView(.vertical, showsIndicators: false) {
                            ImageInspectorView(item: item, onCopyText: copyTransformedText, onShowToast: { onShowToast?($0) })
                                .padding(14)
                        }
                    case .color:
                        ScrollView(.vertical, showsIndicators: false) {
                            ColorInspectorView(item: item, onCopyText: copyTransformedText)
                                .padding(14)
                        }
                    case .url:
                        ScrollView(.vertical, showsIndicators: false) {
                            URLInspectorView(item: item, onCopyText: copyTransformedText)
                                .padding(14)
                        }
                    case .file:
                        ScrollView(.vertical, showsIndicators: false) {
                            FileInspectorView(item: item)
                                .padding(14)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("请从左侧选择一条剪贴板记录")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: item?.id) {
            showFullText = false
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private func copyTransformedText(_ text: String, notice: String) {
        ClipboardMonitor.shared.isSelfCopying = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
        SoundManager.shared.playCopy()
        onShowToast?(notice)
    }
}
