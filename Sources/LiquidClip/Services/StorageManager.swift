/**
 * [INPUT]: 依赖 SQLiteStore、ImageCacheStore、OCRService、ClipItem、ClipGroup 与 AppSettings
 * [OUTPUT]: 提供全局单例 StorageManager，负责 SQLite3+FTS5 增量持久化、O(1) 指纹去重、异步检索、旧 JSON 无损迁移与媒体缓存/OCR 协调
 * [POS]: 应用数据持久化与媒体存储协调中心，上承 ClipboardMonitor，下接 ViewModels 与视图层
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

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
    private let dbFileURL: URL
    private let imagesFolderURL: URL
    private let queue = DispatchQueue(label: "com.liquidclip.storage", qos: .utility)
    private var sqliteStore: SQLiteStore?
    private let imageStore: ImageCacheStore
    
    // Ephemeral privacy-mode item IDs (kept purely in memory, never written to disk)
    private var ephemeralItemIds: Set<UUID> = []
    // O(1) duplicate lookup index mapping ClipItem.contentFingerprint -> ClipItem.id
    private var idByFingerprint: [String: UUID] = [:]
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportURL = appSupport.appendingPathComponent("LiquidClip", isDirectory: true)
        self.clipsFileURL = appSupportURL.appendingPathComponent("clips.json")
        self.groupsFileURL = appSupportURL.appendingPathComponent("groups.json")
        self.dbFileURL = appSupportURL.appendingPathComponent("liquidclip.db")
        self.imagesFolderURL = appSupportURL.appendingPathComponent("images", isDirectory: true)
        self.imageStore = ImageCacheStore(imagesFolderURL: imagesFolderURL, queue: queue)
        
        createDirectoriesIfNeeded()
        loadInitialState()
    }
    
    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imagesFolderURL, withIntermediateDirectories: true)
    }
    
    private var isPrivacyMode: Bool {
        AppSettings.shared.privacyMode
    }
    
    public var dataDirectoryURL: URL {
        appSupportURL
    }
    
    public func computeStorageFootprintAsync() async -> (totalBytes: Int64, imageCount: Int) {
        let dbURL = dbFileURL
        let imagesURL = imagesFolderURL
        return await withCheckedContinuation { continuation in
            queue.async {
                let fm = FileManager.default
                var totalBytes: Int64 = 0
                var imageCount = 0
                
                let dbFiles = [
                    dbURL,
                    URL(fileURLWithPath: dbURL.path + "-wal"),
                    URL(fileURLWithPath: dbURL.path + "-shm")
                ]
                for file in dbFiles {
                    if let attrs = try? fm.attributesOfItem(atPath: file.path),
                       let size = attrs[.size] as? NSNumber {
                        totalBytes += size.int64Value
                    }
                }
                
                if let imgFiles = try? fm.contentsOfDirectory(
                    at: imagesURL,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for file in imgFiles {
                        imageCount += 1
                        if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
                           let size = values.fileSize {
                            totalBytes += Int64(size)
                        }
                    }
                }
                continuation.resume(returning: (totalBytes, imageCount))
            }
        }
    }
    
    // MARK: - Persistence & One-Time JSON -> SQLite3 Migration

    /// Privacy mode semantics:
    /// - Enable: pause all disk/SQLite writes; new items & images stay strictly in memory without deleting existing groups/history.
    /// - Disable: purge ephemeral session items & memory images; persisted SQLite state remains intact.
    public func applyPrivacyMode(enabled: Bool) {
        if !enabled {
            if !ephemeralItemIds.isEmpty {
                let toPurge = self.items.filter { ephemeralItemIds.contains($0.id) }
                for item in toPurge {
                    if let imgName = item.imageFileName {
                        imageStore.purgeCachedImage(named: imgName)
                    }
                }
                self.items.removeAll { ephemeralItemIds.contains($0.id) }
                ephemeralItemIds.removeAll()
                rebuildFingerprintIndex()
            }
            imageStore.purgeAllMemoryImages()
        }
    }
    
    private func rebuildFingerprintIndex() {
        idByFingerprint.removeAll(keepingCapacity: true)
        for item in items {
            let fp = item.contentFingerprint
            if idByFingerprint[fp] == nil {
                idByFingerprint[fp] = item.id
            }
        }
    }
    
    private func loadInitialState() {
        let fm = FileManager.default
        let dbExistedBefore = fm.fileExists(atPath: dbFileURL.path)
        self.sqliteStore = SQLiteStore(databaseURL: dbFileURL)
        
        let hasLegacyJSON = fm.fileExists(atPath: clipsFileURL.path) ||
                            fm.fileExists(atPath: clipsFileURL.appendingPathExtension("bak").path) ||
                            fm.fileExists(atPath: groupsFileURL.path) ||
                            fm.fileExists(atPath: groupsFileURL.appendingPathExtension("bak").path)
        
        if !dbExistedBefore && hasLegacyJSON {
            let legacyGroups = loadLegacyGroups() ?? [ClipGroup(name: "常用记录", icon: "bookmark.fill")]
            var legacyItems = loadLegacyItems() ?? []
            for i in 0..<legacyItems.count {
                legacyItems[i].populateCachedMetricsIfNeeded()
            }
            self.groups = legacyGroups
            self.items = legacyItems
            rebuildFingerprintIndex()
            sqliteStore?.replaceAll(groups: legacyGroups, clips: legacyItems)
            archiveLegacyJSONFiles()
            purgeOrphanedImageFiles()
            return
        }
        
        if let store = sqliteStore {
            var loadedGroups = store.loadAllGroups()
            if loadedGroups.isEmpty && !dbExistedBefore {
                let defaultGroup = ClipGroup(name: "常用记录", icon: "bookmark.fill")
                loadedGroups = [defaultGroup]
                store.upsertGroup(defaultGroup)
            }
            self.groups = loadedGroups
            
            var loadedItems = store.loadAllClips()
            for i in 0..<loadedItems.count {
                loadedItems[i].populateCachedMetricsIfNeeded()
            }
            self.items = loadedItems
            rebuildFingerprintIndex()
            purgeOrphanedImageFiles()
        }
    }

    private func loadLegacyItems() -> [ClipItem]? {
        let backupURL = clipsFileURL.appendingPathExtension("bak")
        if let decoded = decodeItems(from: clipsFileURL) {
            return decoded
        } else if FileManager.default.fileExists(atPath: backupURL.path),
                  let decoded = decodeItems(from: backupURL) {
            print("Loaded legacy clips from backup during migration")
            return decoded
        }
        return nil
    }

    private func decodeItems(from url: URL) -> [ClipItem]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            print("Failed to decode clips at \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func loadLegacyGroups() -> [ClipGroup]? {
        let backupURL = groupsFileURL.appendingPathExtension("bak")
        if let decoded = decodeGroups(from: groupsFileURL) {
            return decoded
        } else if FileManager.default.fileExists(atPath: backupURL.path),
                  let decoded = decodeGroups(from: backupURL) {
            print("Loaded legacy groups from backup during migration")
            return decoded
        }
        return nil
    }

    private func decodeGroups(from url: URL) -> [ClipGroup]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ClipGroup].self, from: data)
        } catch {
            print("Failed to decode groups at \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    private func archiveLegacyJSONFiles() {
        let fm = FileManager.default
        let targets = [
            clipsFileURL,
            clipsFileURL.appendingPathExtension("bak"),
            groupsFileURL,
            groupsFileURL.appendingPathExtension("bak")
        ]
        for url in targets where fm.fileExists(atPath: url.path) {
            let archived = url.appendingPathExtension("migrated.bak")
            try? fm.removeItem(at: archived)
            try? fm.moveItem(at: url, to: archived)
        }
    }
    
    /// Background garbage collection of orphaned image files not referenced by any stored ClipItem.
    private func purgeOrphanedImageFiles() {
        let referencedNames = Set(items.compactMap(\.imageFileName))
        imageStore.purgeOrphanedFiles(referencedNames: referencedNames)
    }
    
    /// Hybrid FTS5 + memory search across persisted items and ephemeral privacy-mode items (sync).
    public func searchMatchingIds(query: String) -> Set<UUID> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Set(items.map(\.id))
        }
        var matched = sqliteStore?.searchClipIds(query: trimmed) ?? []
        if isPrivacyMode || sqliteStore == nil {
            for item in items where (sqliteStore == nil || ephemeralItemIds.contains(item.id)) {
                if item.matches(query: trimmed) {
                    matched.insert(item.id)
                }
            }
        }
        return matched
    }

    /// Hybrid FTS5 + memory search across persisted items and ephemeral privacy-mode items (async).
    public func searchMatchingIdsAsync(query: String) async -> Set<UUID> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Set(items.map(\.id))
        }
        let includeEphemeral = isPrivacyMode || sqliteStore == nil
        let ephemeralSnapshot = includeEphemeral
            ? items.filter { sqliteStore == nil || ephemeralItemIds.contains($0.id) }
            : []

        var matched = await sqliteStore?.searchClipIdsAsync(query: trimmed) ?? []
        if !ephemeralSnapshot.isEmpty {
            for item in ephemeralSnapshot where item.matches(query: trimmed) {
                matched.insert(item.id)
            }
        }
        return matched
    }
    
    // MARK: - Group Management
    @discardableResult
    public func createGroup(name: String, icon: String = "folder.fill") -> ClipGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "新建分组" : trimmed
        let newGroup = ClipGroup(name: finalName, icon: icon)
        self.groups.append(newGroup)
        if !isPrivacyMode {
            sqliteStore?.upsertGroup(newGroup)
        }
        return newGroup
    }
    
    public func updateGroup(id: UUID, name: String, icon: String) {
        if let idx = self.groups.firstIndex(where: { $0.id == id }) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.groups[idx].name = trimmed
            }
            self.groups[idx].icon = icon
            if !isPrivacyMode {
                sqliteStore?.upsertGroup(self.groups[idx])
            }
        }
    }
    
    public func renameGroup(id: UUID, newName: String) {
        if let idx = self.groups.firstIndex(where: { $0.id == id }) {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.groups[idx].name = trimmed
                if !isPrivacyMode {
                    sqliteStore?.upsertGroup(self.groups[idx])
                }
            }
        }
    }
    
    public func deleteGroup(id: UUID) {
        self.groups.removeAll { $0.id == id }
        for i in 0..<self.items.count {
            if self.items[i].groupId == id {
                self.items[i].groupId = nil
            }
        }
        if !isPrivacyMode {
            sqliteStore?.deleteGroup(id: id)
        }
    }
    
    public func assignGroup(itemId: UUID, groupId: UUID?) {
        if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
            self.items[idx].groupId = groupId
            if !isPrivacyMode && !ephemeralItemIds.contains(itemId) {
                sqliteStore?.updateClipGroup(id: itemId, groupId: groupId)
            }
        }
    }
    
    public func group(for id: UUID?) -> ClipGroup? {
        guard let id = id else { return nil }
        return groups.first(where: { $0.id == id })
    }
    
    // MARK: - Clip Items Management
    public func addClip(_ item: ClipItem) {
        let fingerprint = item.contentFingerprint
        if let existingId = idByFingerprint[fingerprint],
           let existingIndex = self.items.firstIndex(where: { $0.id == existingId }) {
            var existing = self.items.remove(at: existingIndex)
            existing.updatedAt = Date()
            existing.createdAt = Date() // Move to top
            self.items.insert(existing, at: 0)
            if !isPrivacyMode && !ephemeralItemIds.contains(existing.id) {
                sqliteStore?.upsertClip(existing)
            }
        } else {
            if isPrivacyMode {
                ephemeralItemIds.insert(item.id)
            } else {
                sqliteStore?.upsertClip(item)
            }
            idByFingerprint[fingerprint] = item.id
            self.items.insert(item, at: 0)
        }
        
        self.enforceHistoryLimit()
    }
    
    // Enforce history limit for transient unpinned items ONLY
    // Items that are PINNED or in a CUSTOM GROUP are NEVER automatically removed!
    public func enforceHistoryLimit() {
        let maxCount = AppSettings.shared.maxHistoryCount
        let protectedItems = items.filter { $0.isPinned || $0.groupId != nil }
        let transientItems = items.filter { !$0.isPinned && $0.groupId == nil }
        
        let allowedTransient = max(0, maxCount - protectedItems.count)
        if transientItems.count > allowedTransient {
            let candidates = transientItems.suffix(transientItems.count - allowedTransient)
            let toRemove = isPrivacyMode ? candidates.filter { ephemeralItemIds.contains($0.id) } : Array(candidates)
            guard !toRemove.isEmpty else { return }
            
            let removeIds = Set(toRemove.map(\.id))
            for item in toRemove {
                let fp = item.contentFingerprint
                if idByFingerprint[fp] == item.id {
                    idByFingerprint.removeValue(forKey: fp)
                }
                if let imgName = item.imageFileName {
                    imageStore.deleteImageFile(named: imgName)
                }
                ephemeralItemIds.remove(item.id)
            }
            self.items.removeAll { removeIds.contains($0.id) }
            if !isPrivacyMode {
                sqliteStore?.deleteClips(ids: Array(removeIds))
            }
        }
    }
    
    public func togglePin(id: UUID) {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            self.items[index].isPinned.toggle()
            if !isPrivacyMode && !ephemeralItemIds.contains(id) {
                sqliteStore?.updateClipPin(id: id, isPinned: self.items[index].isPinned)
            }
        }
    }
    
    public func updateOCRText(id: UUID, text: String?) {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            self.items[index].ocrText = text
            if !isPrivacyMode && !ephemeralItemIds.contains(id) {
                sqliteStore?.updateClipOCR(id: id, ocrText: text)
            }
        }
    }
    
    public func deleteItem(id: UUID) {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            let item = self.items.remove(at: index)
            let fp = item.contentFingerprint
            if idByFingerprint[fp] == item.id {
                idByFingerprint.removeValue(forKey: fp)
            }
            ephemeralItemIds.remove(item.id)
            if let imgName = item.imageFileName {
                imageStore.deleteImageFile(named: imgName)
            }
            if !isPrivacyMode {
                sqliteStore?.deleteClips(ids: [id])
            }
        }
    }
    
    // Clear only unpinned AND ungrouped items!
    // Pinned items and items in custom groups are NEVER cleared!
    public func clearUnpinned() {
        let toRemove = self.items.filter { !$0.isPinned && $0.groupId == nil }
        for item in toRemove {
            let fp = item.contentFingerprint
            if idByFingerprint[fp] == item.id {
                idByFingerprint.removeValue(forKey: fp)
            }
            ephemeralItemIds.remove(item.id)
            if let imgName = item.imageFileName {
                imageStore.deleteImageFile(named: imgName)
            }
        }
        let removedIds = toRemove.map(\.id)
        self.items.removeAll { !$0.isPinned && $0.groupId == nil }
        if !isPrivacyMode && !removedIds.isEmpty {
            sqliteStore?.deleteClips(ids: removedIds)
        }
    }
    
    // MARK: - Background Image Ingestion, Deduplication & Auto-OCR

    public func ingestImageDataAsync(
        rawPNG: Data?,
        rawTIFF: Data?,
        filePaths: [String]?,
        sourceAppName: String,
        sourceBundleId: String
    ) {
        queue.async { [weak self] in
            guard let prepared = ImageCacheStore.prepareImageFromPasteboardData(rawPNG: rawPNG, rawTIFF: rawTIFF) else {
                return
            }
            DispatchQueue.main.async {
                self?.finalizeIngestedImage(
                    prepared,
                    filePaths: filePaths,
                    sourceAppName: sourceAppName,
                    sourceBundleId: sourceBundleId
                )
            }
        }
    }
    
    public func ingestImageFileAsync(
        path: String,
        paths: [String],
        sourceAppName: String,
        sourceBundleId: String
    ) {
        queue.async { [weak self] in
            if let prepared = ImageCacheStore.prepareImageFromFile(path: path) {
                DispatchQueue.main.async {
                    self?.finalizeIngestedImage(
                        prepared,
                        filePaths: paths,
                        sourceAppName: sourceAppName,
                        sourceBundleId: sourceBundleId
                    )
                }
            } else {
                DispatchQueue.main.async {
                    let fallbackItem = ClipItem(
                        type: .file,
                        filePaths: paths,
                        sourceAppName: sourceAppName,
                        sourceAppBundleId: sourceBundleId
                    )
                    self?.addClip(fallbackItem)
                }
            }
        }
    }
    
    private func finalizeIngestedImage(
        _ prepared: PreparedImage,
        filePaths: [String]?,
        sourceAppName: String,
        sourceBundleId: String
    ) {
        let imageFP = "i:\(prepared.sha256)"
        if let existingId = idByFingerprint[imageFP],
           let existingIndex = self.items.firstIndex(where: { $0.id == existingId }) {
            var existing = self.items.remove(at: existingIndex)
            existing.updatedAt = Date()
            existing.createdAt = Date()
            self.items.insert(existing, at: 0)
            if !isPrivacyMode && !ephemeralItemIds.contains(existing.id) {
                sqliteStore?.upsertClip(existing)
            }
            self.enforceHistoryLimit()
            return
        }
        
        let fileName = "\(UUID().uuidString).png"
        let decodedImage = imageStore.storeNewImage(fileName: fileName, pngData: prepared.pngData, isPrivacyMode: isPrivacyMode)
        
        let item = ClipItem(
            type: .image,
            imageFileName: fileName,
            imageHash: prepared.sha256,
            imageWidth: prepared.width,
            imageHeight: prepared.height,
            filePaths: filePaths,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceBundleId
        )
        addClip(item)
        
        if AppSettings.shared.enableAutoOCR, let ocrImage = decodedImage {
            let targetId = item.id
            Task { @MainActor [weak self] in
                if let recognized = await OCRService.recognizeText(from: ocrImage) {
                    self?.updateOCRText(id: targetId, text: recognized)
                }
            }
        }
    }
    
    // MARK: - Media Store Delegation
    
    public func imageFileURL(named fileName: String) -> URL? {
        imageStore.imageFileURL(named: fileName)
    }

    public func loadImagePNGData(named fileName: String) -> Data? {
        imageStore.loadPNGData(named: fileName)
    }

    public func loadImagePNGDataAsync(named fileName: String) async -> Data? {
        await imageStore.loadPNGDataAsync(named: fileName)
    }
    
    public func saveImage(_ image: NSImage) -> (fileName: String, width: Double, height: Double)? {
        imageStore.saveImageSync(image, isPrivacyMode: isPrivacyMode)
    }
    
    public func cachedImage(named fileName: String) -> NSImage? {
        imageStore.cachedImage(named: fileName)
    }
    
    public func cachedImage(fromFilePath path: String) -> NSImage? {
        imageStore.cachedImage(fromFilePath: path)
    }
    
    public func loadImage(named fileName: String) -> NSImage? {
        imageStore.loadImage(named: fileName)
    }
    
    public func loadImage(fromFilePath path: String) -> NSImage? {
        imageStore.loadImage(fromFilePath: path)
    }
    
    public func loadImageAsync(named fileName: String) async -> NSImage? {
        await imageStore.loadImageAsync(named: fileName)
    }
    
    public func loadImageAsync(fromFilePath path: String) async -> NSImage? {
        await imageStore.loadImageAsync(fromFilePath: path)
    }
    
    public func cachedThumbnail(named fileName: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        imageStore.cachedThumbnail(named: fileName, maxPixelSize: maxPixelSize)
    }
    
    public func cachedThumbnail(forFilePath path: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        imageStore.cachedThumbnail(forFilePath: path, maxPixelSize: maxPixelSize)
    }
    
    public func loadThumbnailAsync(named fileName: String, maxPixelSize: CGFloat = 80) async -> NSImage? {
        await imageStore.loadThumbnailAsync(named: fileName, maxPixelSize: maxPixelSize)
    }
    
    public func loadThumbnailAsync(forFilePath path: String, maxPixelSize: CGFloat = 80) async -> NSImage? {
        await imageStore.loadThumbnailAsync(forFilePath: path, maxPixelSize: maxPixelSize)
    }
    
    public func loadThumbnail(named fileName: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        imageStore.loadThumbnail(named: fileName, maxPixelSize: maxPixelSize)
    }
    
    public func loadThumbnail(forFilePath path: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        imageStore.loadThumbnail(forFilePath: path, maxPixelSize: maxPixelSize)
    }
}
