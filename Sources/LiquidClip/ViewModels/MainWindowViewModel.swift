/**
 * [INPUT]: 依赖 StorageManager、AppSettings、PasteSimulator 与 SoundManager
 * [OUTPUT]: 提供主窗口状态与交互控制器 MainWindowViewModel，封装筛选、FTS5 检索、快捷键分发与粘贴调度
 * [POS]: MVVM 协调层，解耦 MainWindowView 的 UI 渲染与业务逻辑
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import SwiftUI
import AppKit

@MainActor
public final class MainWindowViewModel: ObservableObject {
    @Published public var searchText: String = ""
    @Published public var selectedFilter: ClipFilter = .all
    @Published public var selectedGroupId: UUID? = nil
    @Published public var selectedItemId: UUID? = nil
    @Published public var keyboardScrollTarget: UUID? = nil
    @Published public var showSettings: Bool = false
    @Published public var showNewGroupModal: Bool = false
    @Published public var editingGroup: ClipGroup? = nil
    @Published public var toastMessage: String? = nil
    @Published public var dismissedUpdateVersion: String? = nil
    @Published public var panelShowToken: Int = 0
    @Published public var isAccessibilityGranted: Bool = PasteSimulator.shared.isAccessibilityTrusted
    @Published public var dismissedAccessibilityBanner: Bool = false
    
    public init() {}
    
    public func filteredItems(
        from items: [ClipItem],
        filter: ClipFilter? = nil,
        groupId: UUID?? = nil,
        search: String? = nil
    ) -> [ClipItem] {
        let activeFilter = filter ?? selectedFilter
        let activeGroupId = groupId ?? selectedGroupId
        let activeSearch = search ?? searchText
        
        var list = items
        if let gId = activeGroupId {
            list = list.filter { $0.groupId == gId }
        } else {
            switch activeFilter {
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
        
        let trimmed = activeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let matchedIds = StorageManager.shared.searchMatchingIds(query: trimmed)
            list = list.filter { matchedIds.contains($0.id) }
        }
        return list
    }
    
    public func summaryMetrics(
        for items: [ClipItem],
        groups: [ClipGroup]
    ) -> (groupCounts: [UUID: Int], pinnedCount: Int, groupMap: [UUID: ClipGroup]) {
        var groupCounts: [UUID: Int] = [:]
        var pinnedCount = 0
        for item in items {
            if item.isPinned { pinnedCount += 1 }
            if let gId = item.groupId { groupCounts[gId, default: 0] += 1 }
        }
        let groupMap = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return (groupCounts, pinnedCount, groupMap)
    }
    
    public func currentSelectedItem(in items: [ClipItem]) -> ClipItem? {
        if let id = selectedItemId, let found = items.first(where: { $0.id == id }) {
            return found
        }
        return items.first
    }
    
    public func selectFilter(_ filter: ClipFilter) {
        selectedFilter = filter
        selectedGroupId = nil
        let newItems = filteredItems(from: StorageManager.shared.items, filter: filter, groupId: .some(nil))
        selectedItemId = newItems.first?.id
        keyboardScrollTarget = newItems.first?.id
    }
    
    public func toggleGroupSelection(_ group: ClipGroup) {
        let nextGroupId = (selectedGroupId == group.id) ? nil : group.id
        selectedGroupId = nextGroupId
        let newItems = filteredItems(from: StorageManager.shared.items, groupId: .some(nextGroupId))
        selectedItemId = newItems.first?.id
        keyboardScrollTarget = newItems.first?.id
    }
    
    public func openNewGroupModal() {
        editingGroup = nil
        showNewGroupModal = true
    }
    
    public func openEditGroupModal(_ group: ClipGroup) {
        editingGroup = group
        showNewGroupModal = true
    }
    
    public func closeGroupModal() {
        showNewGroupModal = false
        editingGroup = nil
    }
    
    public func onPanelWillShow() {
        showSettings = false
        closeGroupModal()
        panelShowToken &+= 1
        refreshAccessibility()
    }
    
    public func onPanelDidHide() {
        showSettings = false
        closeGroupModal()
    }
    
    public func refreshAccessibility() {
        isAccessibilityGranted = PasteSimulator.shared.isAccessibilityTrusted
    }
    
    public func triggerPaste(item: ClipItem, plainTextOnly: Bool = false, onClose: @escaping () -> Void) {
        let success = PasteSimulator.shared.paste(item: item, plainTextOnly: plainTextOnly, closeAction: onClose)
        if !success {
            showToast("已复制到剪贴板，按 ⌘V 粘贴 (开启辅助功能可自动粘贴)")
        }
    }
    
    public func copyItem(_ item: ClipItem) {
        PasteSimulator.shared.copyToPasteboard(item: item)
        SoundManager.shared.playCopy()
        showToast("已复制到剪贴板")
    }
    
    public func copyTextToPasteboard(_ text: String, notice: String) {
        ClipboardMonitor.shared.isSelfCopying = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
        SoundManager.shared.playCopy()
        showToast(notice)
    }
    
    public func deleteItem(_ item: ClipItem, in currentItems: [ClipItem]) {
        if let idx = currentItems.firstIndex(where: { $0.id == item.id }) {
            if currentItems.count > 1 {
                if idx < currentItems.count - 1 {
                    selectedItemId = currentItems[idx + 1].id
                } else if idx > 0 {
                    selectedItemId = currentItems[idx - 1].id
                }
            } else {
                selectedItemId = nil
            }
        }
        StorageManager.shared.deleteItem(id: item.id)
        SoundManager.shared.playDelete()
    }
    
    public func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation {
                if self?.toastMessage == message {
                    self?.toastMessage = nil
                }
            }
        }
    }
    
    public func handleKeyEvent(_ event: NSEvent, onClose: @escaping () -> Void) -> Bool {
        // Escape (53): Close modal -> Clear search -> Close window
        if event.keyCode == 53 {
            if showSettings {
                showSettings = false
                return true
            }
            if showNewGroupModal {
                closeGroupModal()
                return true
            }
            if !searchText.isEmpty {
                searchText = ""
                return true
            }
            onClose()
            return true
        }
        
        // Do not intercept Enter, Backspace, arrows, or 1~9 while a modal overlay is open
        if showSettings || showNewGroupModal {
            return false
        }
        
        let items = filteredItems(from: StorageManager.shared.items)
        guard !items.isEmpty else { return false }
        
        let selectedItem = currentSelectedItem(in: items)
        let currentIdx = items.firstIndex(where: { $0.id == selectedItem?.id }) ?? 0
        
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
        
        // Return / Enter (36) — Shift+Return pastes as plain text
        if event.keyCode == 36, let item = selectedItem {
            let plainOnly = event.modifierFlags.contains(.shift)
            triggerPaste(item: item, plainTextOnly: plainOnly, onClose: onClose)
            return true
        }
        
        // Delete / Backspace (51)
        if event.keyCode == 51, searchText.isEmpty, let item = selectedItem {
            deleteItem(item, in: items)
            return true
        }
        
        // Command + P: Toggle Pin
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "p", let item = selectedItem {
            StorageManager.shared.togglePin(id: item.id)
            return true
        }
        
        // Command + C: Copy selected item
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", let item = selectedItem {
            copyItem(item)
            return true
        }
        
        // Number Keys 1~9: Direct paste when search is empty
        if searchText.isEmpty,
           !event.modifierFlags.contains(.command),
           let char = event.charactersIgnoringModifiers,
           let num = Int(char),
           num >= 1 && num <= 9 {
            let targetIdx = num - 1
            if targetIdx < items.count {
                triggerPaste(item: items[targetIdx], onClose: onClose)
                return true
            }
        }
        
        return false
    }
}
