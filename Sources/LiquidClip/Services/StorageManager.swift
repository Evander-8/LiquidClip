/**
 * [INPUT]: 依赖 ClipItem、ClipGroup、AppSettings 以及 Foundation / AppKit / ImageIO / CryptoKit
 * [OUTPUT]: 提供全局单例 StorageManager，负责剪贴板历史/分组持久化、隐私模式内存隔离、图像异步编解码与缓存、历史上限裁剪和孤儿图片回收
 * [POS]: 应用数据持久化与媒体存储中心，上承 ClipboardMonitor，下接全部 SwiftUI 视图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit
import ImageIO
import CryptoKit

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
    
    // In-memory caching to eliminate redundant disk reads & image decompressions
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var thumbnailKeysByImageName: [String: Set<String>] = [:]
    
    // Ephemeral privacy-mode state (kept purely in memory, never written to disk)
    private var memoryImages: [String: NSImage] = [:]
    private var ephemeralItemIds: Set<UUID> = []
    
    private struct PreparedImage {
        let pngData: Data
        let width: Double
        let height: Double
        let sha256: String
    }
    
    private init() {
        imageCache.countLimit = 60
        imageCache.totalCostLimit = 80 * 1024 * 1024 // 80 MB
        thumbnailCache.countLimit = 300
        thumbnailCache.totalCostLimit = 20 * 1024 * 1024 // 20 MB
        
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

    /// Privacy mode semantics:
    /// - Enable: pause all disk writes; new items & images stay strictly in memory without deleting existing groups/history.
    /// - Disable: purge ephemeral session items & memory images, then resume persistence.
    public func applyPrivacyMode(enabled: Bool) {
        if enabled {
            saveWorkItem?.cancel()
            saveWorkItem = nil
        } else {
            if !ephemeralItemIds.isEmpty {
                let toPurge = self.items.filter { ephemeralItemIds.contains($0.id) }
                for item in toPurge {
                    if let imgName = item.imageFileName {
                        purgeCachedImage(named: imgName)
                    }
                }
                self.items.removeAll { ephemeralItemIds.contains($0.id) }
                ephemeralItemIds.removeAll()
            }
            for imgName in Array(memoryImages.keys) {
                purgeCachedImage(named: imgName)
            }
            memoryImages.removeAll()
            scheduleSave()
        }
    }

    public func loadItems() {
        let backupURL = clipsFileURL.appendingPathExtension("bak")
        var loadedSuccessfully = !FileManager.default.fileExists(atPath: clipsFileURL.path)
        if var decoded = decodeItems(from: clipsFileURL) {
            for i in 0..<decoded.count {
                decoded[i].populateCachedMetricsIfNeeded()
            }
            self.items = decoded
            loadedSuccessfully = true
        } else if FileManager.default.fileExists(atPath: backupURL.path),
                  var decoded = decodeItems(from: backupURL) {
            // Primary file corrupt/incompatible — fall back to last known-good backup and heal.
            for i in 0..<decoded.count {
                decoded[i].populateCachedMetricsIfNeeded()
            }
            self.items = decoded
            loadedSuccessfully = true
            print("Loaded clips from backup after primary decode failure")
            scheduleSave()
        }
        if loadedSuccessfully {
            purgeOrphanedImageFiles()
        }
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

    public func loadGroups() {
        let backupURL = groupsFileURL.appendingPathExtension("bak")
        if let decoded = decodeGroups(from: groupsFileURL) {
            self.groups = decoded
        } else if FileManager.default.fileExists(atPath: backupURL.path),
                  let decoded = decodeGroups(from: backupURL) {
            self.groups = decoded
            print("Loaded groups from backup after primary decode failure")
            scheduleSave()
        } else {
            // Default initial groups if empty / unreadable
            self.groups = [
                ClipGroup(name: "常用记录", icon: "bookmark.fill")
            ]
            self.scheduleSave()
        }
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

    // Debounced save: snapshots on the main actor, encodes & writes OFF the main thread
    // so large histories (500–1000 items with rich text) never hitch the UI.
    public func scheduleSave() {
        if AppSettings.shared.privacyMode { return }
        saveWorkItem?.cancel()

        let clipsSnapshot = self.items
        let groupsSnapshot = self.groups
        let targetClipsURL = self.clipsFileURL
        let targetGroupsURL = self.groupsFileURL

        let work = DispatchWorkItem {
            if let clipsData = try? JSONEncoder().encode(clipsSnapshot) {
                Self.rotateBackup(of: targetClipsURL)
                try? clipsData.write(to: targetClipsURL, options: .atomic)
            }
            if let groupsData = try? JSONEncoder().encode(groupsSnapshot) {
                Self.rotateBackup(of: targetGroupsURL)
                try? groupsData.write(to: targetGroupsURL, options: .atomic)
            }
        }
        saveWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Keeps a one-generation `.bak` of the previously persisted file so a corrupt
    /// or schema-incompatible primary file can be rolled back on next launch.
    nonisolated private static func rotateBackup(of url: URL) {
        let fm = FileManager.default
        let backupURL = url.appendingPathExtension("bak")
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: url, to: backupURL)
    }
    
    /// Background garbage collection of orphaned image files not referenced by any stored ClipItem.
    private func purgeOrphanedImageFiles() {
        let referencedNames = Set(items.compactMap(\.imageFileName))
        let folderURL = imagesFolderURL
        queue.async {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
                return
            }
            for fileURL in files where !referencedNames.contains(fileURL.lastPathComponent) {
                try? fm.removeItem(at: fileURL)
            }
        }
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
            if AppSettings.shared.privacyMode {
                ephemeralItemIds.insert(item.id)
            }
            self.items.insert(item, at: 0)
        }
        
        self.enforceHistoryLimit()
        self.scheduleSave()
    }
    
    // Enforce history limit for transient unpinned items ONLY
    // Items that are PINNED or in a CUSTOM GROUP are NEVER automatically removed!
    public func enforceHistoryLimit() {
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
                ephemeralItemIds.remove(item.id)
            }
            let retainedTransient = Array(transientItems.prefix(allowedTransient))
            let retainedIds = Set(protectedItems.map(\.id) + retainedTransient.map(\.id))
            self.items = self.items.filter { retainedIds.contains($0.id) }
            self.scheduleSave()
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
            ephemeralItemIds.remove(item.id)
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
            ephemeralItemIds.remove(item.id)
            if let imgName = item.imageFileName {
                self.deleteImageFile(name: imgName)
            }
        }
        self.items.removeAll { !$0.isPinned && $0.groupId == nil }
        self.scheduleSave()
    }
    
    // MARK: - Background Image Ingestion & Deduplication

    public func ingestImageDataAsync(
        rawPNG: Data?,
        rawTIFF: Data?,
        filePaths: [String]?,
        sourceAppName: String,
        sourceBundleId: String
    ) {
        queue.async { [weak self] in
            guard let prepared = Self.prepareImageFromPasteboardData(rawPNG: rawPNG, rawTIFF: rawTIFF) else {
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
            if let prepared = Self.prepareImageFromFile(path: path) {
                DispatchQueue.main.async {
                    self?.finalizeIngestedImage(
                        prepared,
                        filePaths: paths,
                        sourceAppName: sourceAppName,
                        sourceBundleId: sourceBundleId
                    )
                }
            } else {
                // Fallback to regular file item if image decoding fails
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
        // Deduplicate by SHA-256 hash before writing any new file
        if let existingIndex = self.items.firstIndex(where: { $0.type == .image && $0.imageHash == prepared.sha256 }) {
            var existing = self.items.remove(at: existingIndex)
            existing.updatedAt = Date()
            existing.createdAt = Date()
            self.items.insert(existing, at: 0)
            self.enforceHistoryLimit()
            self.scheduleSave()
            return
        }
        
        let fileName = "\(UUID().uuidString).png"
        let isPrivacy = AppSettings.shared.privacyMode
        
        if let img = NSImage(data: prepared.pngData) {
            let cost = Self.estimatedMemoryCost(of: img)
            self.imageCache.setObject(img, forKey: fileName as NSString, cost: cost)
            if isPrivacy {
                self.memoryImages[fileName] = img
            }
        }
        
        if !isPrivacy {
            let targetURL = imagesFolderURL.appendingPathComponent(fileName)
            let dataToWrite = prepared.pngData
            queue.async {
                do {
                    try dataToWrite.write(to: targetURL, options: .atomic)
                } catch {
                    print("Failed to write clipboard image asynchronously: \(error)")
                }
            }
        }
        
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
    }
    
    nonisolated private static func prepareImageFromPasteboardData(rawPNG: Data?, rawTIFF: Data?) -> PreparedImage? {
        if let png = rawPNG, let dims = readImagePixelDimensions(from: png) {
            guard dims.width > 2 && dims.height > 2 else { return nil }
            return PreparedImage(
                pngData: png,
                width: dims.width,
                height: dims.height,
                sha256: sha256Hex(of: png)
            )
        }
        if let tiff = rawTIFF,
           let bitmap = NSBitmapImageRep(data: tiff),
           bitmap.pixelsWide > 2,
           bitmap.pixelsHigh > 2,
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return PreparedImage(
                pngData: pngData,
                width: Double(bitmap.pixelsWide),
                height: Double(bitmap.pixelsHigh),
                sha256: sha256Hex(of: pngData)
            )
        }
        return nil
    }
    
    nonisolated private static func prepareImageFromFile(path: String) -> PreparedImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        if ext == "png",
           let data = try? Data(contentsOf: url),
           let dims = readImagePixelDimensions(from: data) {
            guard dims.width > 2 && dims.height > 2 else { return nil }
            return PreparedImage(
                pngData: data,
                width: dims.width,
                height: dims.height,
                sha256: sha256Hex(of: data)
            )
        }
        
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            guard cgImage.width > 2 && cgImage.height > 2 else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                return PreparedImage(
                    pngData: pngData,
                    width: Double(cgImage.width),
                    height: Double(cgImage.height),
                    sha256: sha256Hex(of: pngData)
                )
            }
        }
        
        // Fallback for vector formats such as SVG
        if let img = NSImage(contentsOfFile: path),
           img.size.width > 2,
           img.size.height > 2,
           let tiff = img.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return PreparedImage(
                pngData: pngData,
                width: Double(bitmap.pixelsWide),
                height: Double(bitmap.pixelsHigh),
                sha256: sha256Hex(of: pngData)
            )
        }
        
        return nil
    }
    
    nonisolated private static func readImagePixelDimensions(from data: Data) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        return (width.doubleValue, height.doubleValue)
    }
    
    nonisolated private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    nonisolated private static func estimatedMemoryCost(of image: NSImage) -> Int {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return max(1, rep.pixelsWide * rep.pixelsHigh * 4)
        }
        return max(1, Int(image.size.width * image.size.height * 4))
    }
    
    // MARK: - Synchronous Image Helpers (Kept for Pasteboard & Compatibility)
    
    // Save image to disk (or memory in privacy mode) and return file name
    public func saveImage(_ image: NSImage) -> (fileName: String, width: Double, height: Double)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileName = "\(UUID().uuidString).png"
        let cost = Self.estimatedMemoryCost(of: image)
        
        if AppSettings.shared.privacyMode {
            self.memoryImages[fileName] = image
            self.imageCache.setObject(image, forKey: fileName as NSString, cost: cost)
            return (fileName, Double(bitmap.pixelsWide), Double(bitmap.pixelsHigh))
        }
        
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        do {
            try pngData.write(to: fileURL, options: .atomic)
            self.imageCache.setObject(image, forKey: fileName as NSString, cost: cost)
            return (fileName, Double(bitmap.pixelsWide), Double(bitmap.pixelsHigh))
        } catch {
            print("Failed to save clipboard image: \(error)")
            return nil
        }
    }
    
    public func cachedImage(named fileName: String) -> NSImage? {
        if let mem = memoryImages[fileName] {
            return mem
        }
        return imageCache.object(forKey: fileName as NSString)
    }
    
    public func cachedImage(fromFilePath path: String) -> NSImage? {
        return imageCache.object(forKey: "file_\(path)" as NSString)
    }
    
    public func loadImage(named fileName: String) -> NSImage? {
        if let mem = memoryImages[fileName] {
            return mem
        }
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        if let img = NSImage(contentsOf: fileURL) {
            imageCache.setObject(img, forKey: key, cost: Self.estimatedMemoryCost(of: img))
            return img
        }
        return nil
    }
    
    public func loadImage(fromFilePath path: String) -> NSImage? {
        let key = "file_\(path)" as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if let img = NSImage(contentsOfFile: path) {
            imageCache.setObject(img, forKey: key, cost: Self.estimatedMemoryCost(of: img))
            return img
        }
        return nil
    }
    
    // MARK: - Asynchronous Image & Thumbnail Loading
    
    public func loadImageAsync(named fileName: String) async -> NSImage? {
        if let cached = cachedImage(named: fileName) {
            return cached
        }
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        let loaded: NSImage? = await withCheckedContinuation { continuation in
            queue.async {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(contentsOf: fileURL))
            }
        }
        if let img = loaded {
            imageCache.setObject(img, forKey: fileName as NSString, cost: Self.estimatedMemoryCost(of: img))
        }
        return loaded
    }
    
    public func loadImageAsync(fromFilePath path: String) async -> NSImage? {
        if let cached = cachedImage(fromFilePath: path) {
            return cached
        }
        let loaded: NSImage? = await withCheckedContinuation { continuation in
            queue.async {
                guard FileManager.default.fileExists(atPath: path) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(contentsOfFile: path))
            }
        }
        if let img = loaded {
            imageCache.setObject(img, forKey: "file_\(path)" as NSString, cost: Self.estimatedMemoryCost(of: img))
        }
        return loaded
    }
    
    public func cachedThumbnail(named fileName: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        let key = Self.thumbnailCacheKey(forName: fileName, maxPixelSize: maxPixelSize)
        return thumbnailCache.object(forKey: key as NSString)
    }
    
    public func cachedThumbnail(forFilePath path: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        let key = "thumb_path_\(path)_\(Int(maxPixelSize))"
        return thumbnailCache.object(forKey: key as NSString)
    }
    
    public func loadThumbnailAsync(named fileName: String, maxPixelSize: CGFloat = 80) async -> NSImage? {
        let key = Self.thumbnailCacheKey(forName: fileName, maxPixelSize: maxPixelSize)
        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }
        
        let memOrCachedImage = memoryImages[fileName] ?? imageCache.object(forKey: fileName as NSString)
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        
        let decoded: NSImage? = await withCheckedContinuation { continuation in
            queue.async {
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let thumb = Self.decodeThumbnail(from: fileURL, maxPixelSize: maxPixelSize) {
                    continuation.resume(returning: thumb)
                    return
                }
                if let sourceImg = memOrCachedImage,
                   let tiffData = sourceImg.tiffRepresentation,
                   let thumb = Self.decodeThumbnail(fromData: tiffData, maxPixelSize: maxPixelSize) {
                    continuation.resume(returning: thumb)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
        
        if let thumb = decoded {
            thumbnailCache.setObject(thumb, forKey: key as NSString, cost: Self.estimatedMemoryCost(of: thumb))
            thumbnailKeysByImageName[fileName, default: []].insert(key)
        }
        return decoded
    }
    
    public func loadThumbnailAsync(forFilePath path: String, maxPixelSize: CGFloat = 80) async -> NSImage? {
        let key = "thumb_path_\(path)_\(Int(maxPixelSize))"
        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }
        let fileURL = URL(fileURLWithPath: path)
        let decoded: NSImage? = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.decodeThumbnail(from: fileURL, maxPixelSize: maxPixelSize))
            }
        }
        if let thumb = decoded {
            thumbnailCache.setObject(thumb, forKey: key as NSString, cost: Self.estimatedMemoryCost(of: thumb))
        }
        return decoded
    }
    
    // Fast downscaled thumbnail generation directly via ImageIO without full-image decoding
    public func loadThumbnail(named fileName: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        let key = Self.thumbnailCacheKey(forName: fileName, maxPixelSize: maxPixelSize)
        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }
        if let mem = memoryImages[fileName],
           let tiff = mem.tiffRepresentation,
           let thumb = Self.decodeThumbnail(fromData: tiff, maxPixelSize: maxPixelSize) {
            thumbnailCache.setObject(thumb, forKey: key as NSString, cost: Self.estimatedMemoryCost(of: thumb))
            thumbnailKeysByImageName[fileName, default: []].insert(key)
            return thumb
        }
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        if let thumb = createThumbnail(from: fileURL, cacheKey: key as NSString, maxPixelSize: maxPixelSize) {
            thumbnailKeysByImageName[fileName, default: []].insert(key)
            return thumb
        }
        return nil
    }
    
    public func loadThumbnail(forFilePath path: String, maxPixelSize: CGFloat = 80) -> NSImage? {
        let key = "thumb_path_\(path)_\(Int(maxPixelSize))" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let fileURL = URL(fileURLWithPath: path)
        return createThumbnail(from: fileURL, cacheKey: key, maxPixelSize: maxPixelSize)
    }
    
    private func createThumbnail(from fileURL: URL, cacheKey: NSString, maxPixelSize: CGFloat) -> NSImage? {
        guard let thumb = Self.decodeThumbnail(from: fileURL, maxPixelSize: maxPixelSize) else {
            return nil
        }
        thumbnailCache.setObject(thumb, forKey: cacheKey, cost: Self.estimatedMemoryCost(of: thumb))
        return thumb
    }
    
    nonisolated private static func decodeThumbnail(from fileURL: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        return decodeThumbnail(fromSource: source, maxPixelSize: maxPixelSize)
    }
    
    nonisolated private static func decodeThumbnail(fromData data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return decodeThumbnail(fromSource: source, maxPixelSize: maxPixelSize)
    }
    
    nonisolated private static func decodeThumbnail(fromSource source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    nonisolated private static func thumbnailCacheKey(forName fileName: String, maxPixelSize: CGFloat) -> String {
        "thumb_\(fileName)_\(Int(maxPixelSize))"
    }
    
    private func purgeCachedImage(named name: String) {
        imageCache.removeObject(forKey: name as NSString)
        memoryImages.removeValue(forKey: name)
        if let keys = thumbnailKeysByImageName.removeValue(forKey: name) {
            for key in keys {
                thumbnailCache.removeObject(forKey: key as NSString)
            }
        }
        thumbnailCache.removeObject(forKey: Self.thumbnailCacheKey(forName: name, maxPixelSize: 80) as NSString)
    }
    
    private func deleteImageFile(name: String) {
        purgeCachedImage(named: name)
        let fileURL = imagesFolderURL.appendingPathComponent(name)
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
