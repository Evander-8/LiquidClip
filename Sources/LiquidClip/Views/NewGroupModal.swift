import SwiftUI
import AppKit

public struct NewGroupModal: View {
    @ObservedObject private var storage = StorageManager.shared
    @State private var groupName: String = ""
    @State private var selectedIcon: String = "folder.fill"
    
    public var onClose: () -> Void
    public var onCreated: ((ClipGroup) -> Void)?
    
    private let presetIcons = [
        // Work & Common
        "folder.fill", "bookmark.fill", "briefcase.fill", "tag.fill",
        "star.fill", "heart.fill", "flag.fill",
        // Dev & Tools
        "terminal.fill", "curlybraces", "doc.text.fill", "link",
        "bolt.fill", "sparkles", "archivebox.fill",
        // Productivity & Daily
        "tray.full.fill", "checklist", "lightbulb.fill", "bell.fill",
        "lock.fill", "pin.fill", "bubble.left.and.bubble.right.fill"
    ]
    
    public init(onClose: @escaping () -> Void, onCreated: ((ClipGroup) -> Void)? = nil) {
        self.onClose = onClose
        self.onCreated = onCreated
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 15))
                        .foregroundColor(.accentColor)
                    Text("新建自定义分组")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Description banner
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("分组内的记录永久保留，清空未收藏历史也不会删除分组内容。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
            
            // Input field
            VStack(alignment: .leading, spacing: 6) {
                Text("分组名称")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("例如: 常用工作话术、常用代码片段、待办...", text: $groupName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
            }
            
            // Icon Selector: Scrollable multi-row grid
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("选择图标")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("支持滚动选择")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                        spacing: 8
                    ) {
                        ForEach(presetIcons, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                ZStack {
                                    if selectedIcon == icon {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 32, height: 32)
                                    } else {
                                        Circle()
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(width: 32, height: 32)
                                    }
                                    
                                    Image(systemName: icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(selectedIcon == icon ? .white : .primary)
                                }
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 120)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                )
            }
            
            // Action Buttons
            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    onClose()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                .buttonStyle(.plain)
                
                Button("创建分组") {
                    createAndFinish()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(groupName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                .cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 20)
    }
    
    private func createAndFinish() {
        let trimmed = groupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let group = storage.createGroup(name: trimmed, icon: selectedIcon)
        onCreated?(group)
        onClose()
    }
}
