/**
 * [INPUT]: 依赖 MainWindowViewModel、StorageManager、AppSettings、UpdateChecker、PasteSimulator 与各子视图组件
 * [OUTPUT]: 提供主窗口根视图 MainWindowView，负责液态玻璃布局呈现与事件绑定
 * [POS]: 应用核心 UI 容器，被 AppDelegate 挂载于 FloatingPanel 的 NSHostingView 中
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct MainWindowView: View {
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @StateObject private var viewModel = MainWindowViewModel()
    
    public var onClose: () -> Void
    public var registerKeyHandler: ((@escaping (NSEvent) -> Bool) -> Void)?
    
    public init(onClose: @escaping () -> Void, registerKeyHandler: ((@escaping (NSEvent) -> Bool) -> Void)? = nil) {
        self.onClose = onClose
        self.registerKeyHandler = registerKeyHandler
    }
    
    public var body: some View {
        let currentItems = viewModel.filteredItems(from: storage.items)
        let selectedItem = viewModel.currentSelectedItem(in: currentItems)
        let currentId = selectedItem?.id
        let metrics = viewModel.summaryMetrics(for: storage.items, groups: storage.groups)
        
        return ZStack {
            // Native Frosted Liquid Glass Background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .edgesIgnoringSafeArea(.all)
            
            // Specular reflection gradient at the top edge
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
                updateBanner
                accessibilityBanner
                topBar(currentItems: currentItems)
                
                Divider().opacity(0.35)
                
                // Center Split Area
                HStack(spacing: 0) {
                    leftListColumn(currentItems: currentItems, currentId: currentId, groupMap: metrics.groupMap)
                        .frame(width: 330)
                    
                    Divider().opacity(0.35)
                    
                    ClipDetailView(
                        item: selectedItem,
                        onPaste: {
                            if let item = selectedItem {
                                viewModel.triggerPaste(item: item, onClose: onClose)
                            }
                        },
                        onPastePlainText: {
                            if let item = selectedItem {
                                viewModel.triggerPaste(item: item, plainTextOnly: true, onClose: onClose)
                            }
                        },
                        onCopy: {
                            if let item = selectedItem {
                                viewModel.copyItem(item)
                            }
                        },
                        onTogglePin: {
                            if let item = selectedItem {
                                storage.togglePin(id: item.id)
                            }
                        },
                        onDelete: {
                            if let item = selectedItem {
                                viewModel.deleteItem(item, in: currentItems)
                            }
                        },
                        onShowToast: { msg in
                            viewModel.showToast(msg)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                }
                
                Divider().opacity(0.35)
                
                bottomStatusBar(
                    count: currentItems.count,
                    pinnedCount: metrics.pinnedCount,
                    groupMap: metrics.groupMap
                )
            }
            
            // Settings Modal Overlay
            if viewModel.showSettings {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { viewModel.showSettings = false }
                
                SettingsView(onClose: { viewModel.showSettings = false })
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // New / Edit Group Modal Overlay
            if viewModel.showNewGroupModal {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { viewModel.closeGroupModal() }
                
                NewGroupModal(
                    editingGroup: viewModel.editingGroup,
                    onClose: { viewModel.closeGroupModal() },
                    onCreated: { newGroup in
                        viewModel.selectedGroupId = newGroup.id
                        viewModel.selectedItemId = viewModel.filteredItems(from: storage.items).first?.id
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // Toast Notification
            if let msg = viewModel.toastMessage {
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
                    .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
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
        .onAppear {
            if viewModel.selectedItemId == nil {
                viewModel.selectedItemId = viewModel.filteredItems(from: storage.items).first?.id
            }
            viewModel.refreshAccessibility()
            registerKeyHandler? { event in
                viewModel.handleKeyEvent(event, onClose: onClose)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatingPanelDidHide)) { _ in
            viewModel.onPanelDidHide()
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatingPanelWillShow)) { _ in
            viewModel.onPanelWillShow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLiquidClipSettings)) { _ in
            viewModel.showSettings = true
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var updateBanner: some View {
        if let version = updateChecker.latestVersion, viewModel.dismissedUpdateVersion != version {
            Button {
                if let url = updateChecker.latestReleaseURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("发现新版本 \(version) — 点击前往下载")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                    Spacer()
                    Button(action: { viewModel.dismissedUpdateVersion = version }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.green.opacity(0.10))
            }
            .buttonStyle(.plain)
            .help("前往 GitHub Releases 下载新版本")
        }
    }
    
    @ViewBuilder
    private var accessibilityBanner: some View {
        if settings.autoPasteOnSelect && !viewModel.isAccessibilityGranted && !viewModel.dismissedAccessibilityBanner {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("未开启辅助功能权限，选中记录将仅复制（需手动 ⌘V 粘贴）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                Spacer()
                Button("去授权") {
                    PasteSimulator.shared.openAccessibilitySettings()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(Color.orange.opacity(0.16))
                .cornerRadius(5)
                .buttonStyle(.plain)
                
                Button(action: { viewModel.dismissedAccessibilityBanner = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.10))
        }
    }
    
    @ViewBuilder
    private func topBar(currentItems: [ClipItem]) -> some View {
        let metrics = viewModel.summaryMetrics(for: storage.items, groups: storage.groups)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LiquidSearchBar(text: $viewModel.searchText, focusTrigger: viewModel.panelShowToken)
                    .onChange(of: viewModel.searchText) {
                        viewModel.selectedItemId = viewModel.filteredItems(from: storage.items).first?.id
                    }
                
                GlassIconButton(icon: "gearshape", size: 30) {
                    viewModel.showSettings = true
                }
                .help("偏好设置")
                
                GlassIconButton(icon: "xmark", size: 30) {
                    viewModel.showSettings = false
                    viewModel.closeGroupModal()
                    onClose()
                }
                .help("关闭窗口 (Esc)")
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ClipFilter.allCases) { filter in
                        filterPill(filter)
                    }
                    
                    Divider()
                        .frame(height: 16)
                        .opacity(0.4)
                        .padding(.horizontal, 2)
                    
                    ForEach(storage.groups) { group in
                        groupPill(group, count: metrics.groupCounts[group.id, default: 0])
                    }
                    
                    Button(action: { viewModel.openNewGroupModal() }) {
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
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("新建自定义分组 (防清理保护)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private func leftListColumn(currentItems: [ClipItem], currentId: UUID?, groupMap: [UUID: ClipGroup]) -> some View {
        VStack(spacing: 0) {
            if currentItems.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(currentItems.enumerated()), id: \.element.id) { idx, item in
                                ClipRowView(
                                    item: item,
                                    index: idx,
                                    isSelected: item.id == currentId,
                                    showShortcuts: settings.showShortcutsInList,
                                    group: item.groupId.flatMap { groupMap[$0] },
                                    refreshTick: viewModel.panelShowToken,
                                    onSelect: {
                                        viewModel.selectedItemId = item.id
                                    },
                                    onPaste: {
                                        viewModel.triggerPaste(item: item, onClose: onClose)
                                    },
                                    onPastePlainText: {
                                        viewModel.triggerPaste(item: item, plainTextOnly: true, onClose: onClose)
                                    },
                                    onTogglePin: {
                                        storage.togglePin(id: item.id)
                                    },
                                    onDelete: {
                                        viewModel.deleteItem(item, in: currentItems)
                                    }
                                )
                                .equatable()
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.keyboardScrollTarget) { _, targetId in
                        if let id = targetId {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: nil)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func bottomStatusBar(count: Int, pinnedCount: Int, groupMap: [UUID: ClipGroup]) -> some View {
        HStack {
            HStack(spacing: 4) {
                Text("\(count) 条记录")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                if let gId = viewModel.selectedGroupId, let g = groupMap[gId] {
                    Text("• 分组: \(g.name)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                } else if pinnedCount > 0 {
                    Text("• \(pinnedCount) 收藏")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                hintBadge(key: "↵", label: "粘贴")
                hintBadge(key: "⇧↵", label: "纯文本")
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
    
    @ViewBuilder
    private func filterPill(_ filter: ClipFilter) -> some View {
        let isSelected = viewModel.selectedFilter == filter && viewModel.selectedGroupId == nil
        Button(action: {
            viewModel.selectFilter(filter)
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
            .background(Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04)))
            .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    @ViewBuilder
    private func groupPill(_ group: ClipGroup, count: Int) -> some View {
        let isSelected = viewModel.selectedGroupId == group.id
        Button(action: {
            viewModel.toggleGroupSelection(group)
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
            .background(Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contextMenu {
            Button(action: {
                viewModel.openEditGroupModal(group)
            }) {
                Label("编辑分组 \"\(group.name)\"", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: {
                storage.deleteGroup(id: group.id)
                if viewModel.selectedGroupId == group.id {
                    viewModel.selectedGroupId = nil
                }
            }) {
                Label("删除分组 \"\(group.name)\"", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(viewModel.searchText.isEmpty ? "剪贴板历史为空" : "没有找到匹配的记录")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text(viewModel.searchText.isEmpty ? "复制任意文本、图片或文件后将自动显示在这里" : "换个搜索关键字试试")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    @ViewBuilder
    private func hintBadge(key: String, label: String) -> some View {
        HStack(spacing: 3) {
            KeyboardBadge(key)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
