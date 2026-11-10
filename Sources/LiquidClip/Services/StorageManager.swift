import Foundation
import AppKit

@MainActor
public class StorageManager: ObservableObject {
    public static let shared = StorageManager()
    
    @Published public var items: [ClipItem] = []
    @Published public var groups: [ClipGroup] = []
    
    private let appSupportURL: URL
    private let clipsFileURL: URL
    private let groupsFileURL: URL
    private let imagesFolderURL: URL
    private let queue = DispatchQueue(label: "com.liquidclip.storage", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportURL = appSupport.appendingPathComponent("LiquidClip", isDirectory: true)
        self.clipsFileURL = appSupportURL.appendingPathComponent("clips.json")
        self.groupsFileURL = appSupportURL.appendingPathComponent("groups.json")
        self.imagesFolderURL = appSupportURL.appendingPathComponent("images", isDirectory: true)
        
        createDirectoriesIfNeeded()
        loadGroups()
        loadItems()
    }
    
    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imagesFolderURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Persistence
    public func loadItems() {
        guard FileManager.default.fileExists(atPath: clipsFileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: clipsFileURL)
            let decoded = try JSONDecoder().decode([ClipItem].self, from: data)
            self.items = decoded
        } catch {
            print("Failed to load clips: \(error)")
        }
    }
    
    public func loadGroups() {
        guard FileManager.default.fileExists(atPath: groupsFileURL.path) else {
            // Default initial groups if empty
            self.groups = [
                ClipGroup(name: "常用记录", icon: "bookmark.fill")
            ]
            self.scheduleSave()
            return
        }
        do {
            let data = try Data(contentsOf: groupsFileURL)
            let decoded = try JSONDecoder().decode([ClipGroup].self, from: data)
            self.groups = decoded
        } catch {
            print("Failed to load groups: \(error)")
        }
    }
    
    // Debounced async save
    public func scheduleSave() {
        saveWorkItem?.cancel()
        
        // Encode on main actor
        guard let clipsData = try? JSONEncoder().encode(self.items),
              let groupsData = try? JSONEncoder().encode(self.groups) else { return }
        let targetClipsURL = self.clipsFileURL
        let targetGroupsURL = self.groupsFileURL
        
        let work = DispatchWorkItem {
            try? clipsData.write(to: targetClipsURL, options: .atomic)
            try? groupsData.write(to: targetGroupsURL, options: .atomic)
        }
        saveWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    
    // MARK: - Group Management
    @discardableResult
    public func createGroup(name: String, icon: String = "folder.fill") -> ClipGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "新建分组" : trimmed
        let newGroup = ClipGroup(name: finalName, icon: icon)
        self.groups.append(newGroup)
        self.scheduleSave()
        return newGroup
    }
    
    public func renameGroup(id: UUID, newName: String) {
        if let idx = self.groups.firstIndex(where: { $0.id == id }) {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.groups[idx].name = trimmed
                self.scheduleSave()
            }
        }
    }
    
    public func deleteGroup(id: UUID) {
        self.groups.removeAll { $0.id == id }
        // Ungroup items that belonged to this group (retain in history)
        for i in 0..<self.items.count {
            if self.items[i].groupId == id {
                self.items[i].groupId = nil
            }
        }
        self.scheduleSave()
    }
    
    public func assignGroup(itemId: UUID, groupId: UUID?) {
        if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
            self.items[idx].groupId = groupId
            self.scheduleSave()
        }
    }
    
    public func group(for id: UUID?) -> ClipGroup? {
        guard let id = id else { return nil }
        return groups.first(where: { $0.id == id })
    }
    
    // MARK: - Clip Items Management
    public func addClip(_ item: ClipItem) {
        // Check for duplicate
        if let existingIndex = self.items.firstIndex(where: { $0.contentFingerprint == item.contentFingerprint }) {
            var existing = self.items.remove(at: existingIndex)
            existing.updatedAt = Date()
            existing.createdAt = Date() // Move to top
            self.items.insert(existing, at: 0)
        } else {
            self.items.insert(item, at: 0)
        }
        
        self.enforceHistoryLimit()
        self.scheduleSave()
    }
    
    // Enforce history limit for transient unpinned items ONLY
    // Items that are PINNED or in a CUSTOM GROUP are NEVER automatically removed!
    private func enforceHistoryLimit() {
        let maxCount = AppSettings.shared.maxHistoryCount
        // Protected: Pinned items OR items in a custom group
        let protectedItems = items.filter { $0.isPinned || $0.groupId != nil }
        let transientItems = items.filter { !$0.isPinned && $0.groupId == nil }
        
        let allowedTransient = max(0, maxCount - protectedItems.count)
        if transientItems.count > allowedTransient {
            let toRemove = transientItems.suffix(transientItems.count - allowedTransient)
            for item in toRemove {
                if let imgName = item.imageFileName {
                    deleteImageFile(name: imgName)
                }
            }
            let retainedTransient = Array(transientItems.prefix(allowedTransient))
            let retainedIds = Set(protectedItems.map(\.id) + retainedTransient.map(\.id))
            self.items = self.items.filter { retainedIds.contains($0.id) }
        }
    }
    
    public func togglePin(id: UUID) {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            self.items[index].isPinned.toggle()
            self.scheduleSave()
        }
    }
    
    public func deleteItem(id: UUID) {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            let item = self.items.remove(at: index)
            if let imgName = item.imageFileName {
                self.deleteImageFile(name: imgName)
            }
            self.scheduleSave()
        }
    }
    
    // Clear only unpinned AND ungrouped items!
    // Pinned items and items in custom groups are NEVER cleared!
    public func clearUnpinned() {
        let toRemove = self.items.filter { !$0.isPinned && $0.groupId == nil }
        for item in toRemove {
            if let imgName = item.imageFileName {
                self.deleteImageFile(name: imgName)
            }
        }
        self.items.removeAll { !$0.isPinned && $0.groupId == nil }
        self.scheduleSave()
    }
    
    // Save image to disk and return file name
    public func saveImage(_ image: NSImage) -> (fileName: String, width: Double, height: Double)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileName = "\(UUID().uuidString).png"
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        
        do {
            try pngData.write(to: fileURL)
            return (fileName, Double(bitmap.pixelsWide), Double(bitmap.pixelsHigh))
        } catch {
            print("Failed to save clipboard image: \(error)")
            return nil
        }
    }
    
    public func loadImage(named fileName: String) -> NSImage? {
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return NSImage(contentsOf: fileURL)
    }
    
    private func deleteImageFile(name: String) {
        let fileURL = imagesFolderURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
