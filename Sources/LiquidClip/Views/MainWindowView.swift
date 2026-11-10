import SwiftUI
import AppKit

public struct MainWindowView: View {
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var searchText: String = ""
    @State private var selectedFilter: ClipFilter = .all
    @State private var selectedGroupId: UUID? = nil
    @State private var selectedItemId: UUID? = nil
    @State private var keyboardScrollTarget: UUID? = nil
    @State private var showSettings: Bool = false
    @State private var showNewGroupModal: Bool = false
    @State private var toastMessage: String? = nil
    
    public var onClose: () -> Void
    public var registerKeyHandler: ((@escaping (NSEvent) -> Bool) -> Void)?
    
    public init(onClose: @escaping () -> Void, registerKeyHandler: ((@escaping (NSEvent) -> Bool) -> Void)? = nil) {
        self.onClose = onClose
        self.registerKeyHandler = registerKeyHandler
    }
    
    // Filtered items based on search query, category filter and custom group
    private var filteredItems: [ClipItem] {
        var list = storage.items
        
        if let groupId = selectedGroupId {
            list = list.filter { $0.groupId == groupId }
        } else {
            switch selectedFilter {
            case .all:
                break
            case .text:
                list = list.filter { $0.type == .text }
            case .image:
                list = list.filter { $0.type == .image }
            case .color:
                list = list.filter { $0.type == .color }
            case .url:
                list = list.filter { $0.type == .url }
            case .file:
                list = list.filter { $0.type == .file }
            case .pinned:
                list = list.filter { $0.isPinned }
            }
        }
        
        if !searchText.isEmpty {
            list = list.filter { $0.matches(query: searchText) }
        }
        
        return list
    }
    
    // Currently selected item by UUID (immune to index shifts)
    private var currentSelectedItem: ClipItem? {
        let items = filteredItems
        if let id = selectedItemId, let found = items.first(where: { $0.id == id }) {
            return found
        }
        return items.first
    }
    
    public var body: some View {
        ZStack {
            // Native Frosted Liquid Glass Background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .edgesIgnoringSafeArea(.all)
            
            // Specular reflection gradient at the top edge (liquid sheen)
            VStack {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.18), location: 0),
                        .init(color: Color.white.opacity(0.04), location: 0.5),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 3)
                Spacer()
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // MARK: - Top Liquid Search & Filter Bar
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        // Liquid Search Box
                        LiquidSearchBar(text: $searchText)
                            .onChange(of: searchText) {
                                selectedItemId = filteredItems.first?.id
                            }
                        
                        // Settings Button
                        GlassIconButton(icon: "gearshape", size: 30) {
                            showSettings = true
                        }
                        .help("偏好设置")
                        
                        // Close Button
                        GlassIconButton(icon: "xmark", size: 30) {
                            showSettings = false
                            showNewGroupModal = false
                            onClose()
                        }
                        .help("关闭窗口 (Esc)")
                    }
                    
                    // Filter Pills & Custom Group Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ClipFilter.allCases) { filter in
                                filterPill(filter)
                            }
                            
                            Divider()
                                .frame(height: 16)
                                .opacity(0.4)
                                .padding(.horizontal, 2)
                            
                            // Custom Groups
                            ForEach(storage.groups) { group in
                                groupPill(group)
                            }
                            
                            // Add Group Button
                            Button(action: { showNewGroupModal = true }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("分组")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("新建自定义分组 (防清理保护)")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                Divider().opacity(0.35)
                
                // MARK: - Center Split Area
                HStack(spacing: 0) {
                    // Left Column: Clips List
                    VStack(spacing: 0) {
                        if filteredItems.isEmpty {
                            emptyStateView
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: true) {
                                    VStack(spacing: 4) {
                                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                                            ClipRowView(
                                                item: item,
                                                index: idx,
                                                isSelected: item.id == currentSelectedItem?.id,
                                                onSelect: {
                                                    selectedItemId = item.id
                                                },
                                                onPaste: {
                                                    triggerPaste(item: item)
                                                },
                                                onTogglePin: {
                                                    storage.togglePin(id: item.id)
                                                },
                                                onDelete: {
                                                    deleteItem(item: item)
                                                }
                                            )
                                            .id(item.id)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .onChange(of: keyboardScrollTarget) { _, targetId in
                                    if let id = targetId {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            proxy.scrollTo(id, anchor: nil)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 330)
                    
                    Divider().opacity(0.35)
                    
                    // Right Column: Liquid Inspector
                    ClipDetailView(
                        item: currentSelectedItem,
                        onPaste: {
                            if let item = currentSelectedItem {
                                triggerPaste(item: item)
                            }
                        },
                        onCopy: {
                            if let item = currentSelectedItem {
                                PasteSimulator.shared.copyToPasteboard(item: item)
                                SoundManager.shared.playCopy()
                                showToast("已复制到剪贴板")
                            }
                        },
                        onTogglePin: {
                            if let item = currentSelectedItem {
                                storage.togglePin(id: item.id)
                            }
                        },
                        onDelete: {
                            if let item = currentSelectedItem {
                                deleteItem(item: item)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                }
                
                Divider().opacity(0.35)
                
                // MARK: - Bottom Status & Keyboard Shortcuts Bar
                HStack {
                    // Item Count
                    HStack(spacing: 4) {
                        Text("\(filteredItems.count) 条记录")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if let gId = selectedGroupId, let g = storage.group(for: gId) {
                            Text("• 分组: \(g.name)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        } else {
                            let pinnedCount = storage.items.filter { $0.isPinned }.count
                            if pinnedCount > 0 {
                                Text("• \(pinnedCount) 收藏")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange.opacity(0.9))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Keyboard Hints
                    HStack(spacing: 8) {
                        hintBadge(key: "↵", label: "粘贴")
                        hintBadge(key: "1-9", label: "直达")
                        hintBadge(key: "⌘P", label: "收藏")
                        hintBadge(key: "⌫", label: "删除")
                        hintBadge(key: "Esc", label: "关闭")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))
            }
            
            // Settings Modal Overlay
            if showSettings {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { showSettings = false }
                
                SettingsView(onClose: { showSettings = false })
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // New Group Modal Overlay
            if showNewGroupModal {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { showNewGroupModal = false }
                
                NewGroupModal(onClose: { showNewGroupModal = false }, onCreated: { newGroup in
                    selectedGroupId = newGroup.id
                    selectedItemId = filteredItems.first?.id
                })
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // Toast Notification
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 10)
                    .padding(.bottom, 45)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: 820, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.28), location: 0),
                            .init(color: Color.white.opacity(0.08), location: 0.5),
                            .init(color: Color.black.opacity(0.2), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        // Global Keyboard Event Handling inside window
        .background(
            KeyboardEventHandler { event in
                handleKeyEvent(event)
            }
        )
        .onAppear {
            if selectedItemId == nil {
                selectedItemId = filteredItems.first?.id
            }
            registerKeyHandler? { event in
                handleKeyEvent(event)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatingPanelDidHide)) { _ in
            showSettings = false
            showNewGroupModal = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatingPanelWillShow)) { _ in
            showSettings = false
            showNewGroupModal = false
        }
    }
    
    // Filter Pill Button
    @ViewBuilder
    private func filterPill(_ filter: ClipFilter) -> some View {
        let isSelected = selectedFilter == filter && selectedGroupId == nil
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                selectedFilter = filter
                selectedGroupId = nil
                selectedItemId = filteredItems.first?.id
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 10))
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // Group Pill Button
    @ViewBuilder
    private func groupPill(_ group: ClipGroup) -> some View {
        let isSelected = selectedGroupId == group.id
        let count = storage.items.filter { $0.groupId == group.id }.count
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                if selectedGroupId == group.id {
                    selectedGroupId = nil
                } else {
                    selectedGroupId = group.id
                }
                selectedItemId = filteredItems.first?.id
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: group.icon)
                    .font(.system(size: 10))
                Text(group.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: {
                storage.deleteGroup(id: group.id)
                if selectedGroupId == group.id {
                    selectedGroupId = nil
                }
            }) {
                Label("删除分组 \"\(group.name)\"", systemImage: "trash")
            }
        }
    }
    
    // Empty state graphic
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(searchText.isEmpty ? "剪贴板历史为空" : "没有找到匹配的记录")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "复制任意文本、图片或文件后将自动显示在这里" : "换个搜索关键字试试")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    // Keyboard Hint Pill
    @ViewBuilder
    private func hintBadge(key: String, label: String) -> some View {
        HStack(spacing: 3) {
            KeyboardBadge(key)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // Trigger Paste
    private func triggerPaste(item: ClipItem) {
        let success = PasteSimulator.shared.paste(item: item, closeAction: onClose)
        if !success {
            showToast("已复制到剪贴板，按 ⌘V 粘贴 (开启辅助功能可自动粘贴)")
        }
    }
    
    // Delete item
    private func deleteItem(item: ClipItem) {
        let items = filteredItems
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            if items.count > 1 {
                if idx < items.count - 1 {
                    selectedItemId = items[idx + 1].id
                } else if idx > 0 {
                    selectedItemId = items[idx - 1].id
                }
            } else {
                selectedItemId = nil
            }
        }
        
        storage.deleteItem(id: item.id)
        SoundManager.shared.playDelete()
    }
    
    // Show Toast
    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
    
    // Handle Window Key Events
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Escape (53): Close modal -> Clear search -> Close window
        if event.keyCode == 53 {
            if showSettings {
                showSettings = false
                return true
            }
            if showNewGroupModal {
                showNewGroupModal = false
                return true
            }
            if !searchText.isEmpty {
                searchText = ""
                return true
            }
            onClose()
            return true
        }
        
        let items = filteredItems
        guard !items.isEmpty else {
            return false
        }
        
        let currentIdx = items.firstIndex(where: { $0.id == currentSelectedItem?.id }) ?? 0
        
        // Down Arrow (125)
        if event.keyCode == 125 {
            if currentIdx < items.count - 1 {
                let nextId = items[currentIdx + 1].id
                selectedItemId = nextId
                keyboardScrollTarget = nextId
            }
            return true
        }
        
        // Up Arrow (126)
        if event.keyCode == 126 {
            if currentIdx > 0 {
                let prevId = items[currentIdx - 1].id
                selectedItemId = prevId
                keyboardScrollTarget = prevId
            }
            return true
        }
        
        // Return / Enter (36)
        if event.keyCode == 36 {
            if let item = currentSelectedItem {
                triggerPaste(item: item)
                return true
            }
        }
        
        // Delete / Backspace (51)
        if event.keyCode == 51 {
            if searchText.isEmpty, let item = currentSelectedItem {
                deleteItem(item: item)
                return true
            }
        }
        
        // Command + P: Toggle Pin
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "p" {
            if let item = currentSelectedItem {
                storage.togglePin(id: item.id)
                return true
            }
        }
        
        // Command + C: Copy selected item
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if let item = currentSelectedItem {
                PasteSimulator.shared.copyToPasteboard(item: item)
                SoundManager.shared.playCopy()
                showToast("已复制到剪贴板")
                return true
            }
        }
        
        // Number Keys 1~9: Direct paste (only if not actively typing into search with numbers)
        if let char = event.charactersIgnoringModifiers, let num = Int(char), num >= 1 && num <= 9 {
            let targetIdx = num - 1
            if targetIdx < items.count && !event.modifierFlags.contains(.command) {
                if searchText.isEmpty {
                    let targetItem = items[targetIdx]
                    triggerPaste(item: targetItem)
                    return true
                }
            }
        }
        
        return false
    }
}

// Transparent view that captures NSEvents
struct KeyboardEventHandler: NSViewRepresentable {
    let handler: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handler = handler
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.handler = handler
    }
    
    class KeyView: NSView {
        var handler: ((NSEvent) -> Bool)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if let handler = handler, handler(event) {
                return
            }
            super.keyDown(with: event)
        }
    }
}
