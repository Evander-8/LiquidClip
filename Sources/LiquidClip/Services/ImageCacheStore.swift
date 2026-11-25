/**
 * [INPUT]: 依赖 Foundation、AppKit、ImageIO 与 CryptoKit
 * [OUTPUT]: 提供图像媒体与缓存管理器 ImageCacheStore，封装后台 PNG 编解码、SHA-256 哈希、原始 PNG 字节异步读取、NSCache 字节限额与异步缩略图加载
 * [POS]: StorageManager 的媒体子引擎，专责图像磁盘文件与内存缓存生命周期
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit
import ImageIO
import CryptoKit

public struct PreparedImage: Sendable {
    public let pngData: Data
    public let width: Double
    public let height: Double
    public let sha256: String
}

@MainActor
public final class ImageCacheStore {
    public let imagesFolderURL: URL
    private let queue: DispatchQueue
    
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var thumbnailKeysByImageName: [String: Set<String>] = [:]
    private var memoryImages: [String: NSImage] = [:]
    private var memoryImageData: [String: Data] = [:]
    
    public init(imagesFolderURL: URL, queue: DispatchQueue) {
        self.imagesFolderURL = imagesFolderURL
        self.queue = queue
        self.imageCache.countLimit = 60
        self.imageCache.totalCostLimit = 80 * 1024 * 1024 // 80 MB
        self.thumbnailCache.countLimit = 300
        self.thumbnailCache.totalCostLimit = 20 * 1024 * 1024 // 20 MB
    }
    
    // MARK: - Privacy Memory Store & Purge
    
    public func storeNewImage(
        fileName: String,
        pngData: Data,
        isPrivacyMode: Bool
    ) -> NSImage? {
        let decodedImage = NSImage(data: pngData)
        if let img = decodedImage {
            let cost = Self.estimatedMemoryCost(of: img)
            imageCache.setObject(img, forKey: fileName as NSString, cost: cost)
            if isPrivacyMode {
                memoryImages[fileName] = img
                memoryImageData[fileName] = pngData
            }
        } else if isPrivacyMode {
            memoryImageData[fileName] = pngData
        }
        if !isPrivacyMode {
            let targetURL = imagesFolderURL.appendingPathComponent(fileName)
            queue.async {
                do {
                    try pngData.write(to: targetURL, options: .atomic)
                } catch {
                    print("Failed to write clipboard image asynchronously: \(error)")
                }
            }
        }
        return decodedImage
    }
    
    public func saveImageSync(_ image: NSImage, isPrivacyMode: Bool) -> (fileName: String, width: Double, height: Double)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileName = "\(UUID().uuidString).png"
        let cost = Self.estimatedMemoryCost(of: image)
        
        if isPrivacyMode {
            memoryImages[fileName] = image
            memoryImageData[fileName] = pngData
            imageCache.setObject(image, forKey: fileName as NSString, cost: cost)
            return (fileName, Double(bitmap.pixelsWide), Double(bitmap.pixelsHigh))
        }
        
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        do {
            try pngData.write(to: fileURL, options: .atomic)
            imageCache.setObject(image, forKey: fileName as NSString, cost: cost)
            return (fileName, Double(bitmap.pixelsWide), Double(bitmap.pixelsHigh))
        } catch {
            print("Failed to save clipboard image: \(error)")
            return nil
        }
    }
    
    public func imageFileURL(named fileName: String) -> URL? {
        if memoryImages[fileName] != nil {
            return nil
        }
        let url = imagesFolderURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    public func purgeAllMemoryImages() {
        for imgName in Array(memoryImages.keys) {
            purgeCachedImage(named: imgName)
        }
        memoryImages.removeAll()
        memoryImageData.removeAll()
    }
    
    public func purgeCachedImage(named name: String) {
        imageCache.removeObject(forKey: name as NSString)
        memoryImages.removeValue(forKey: name)
        memoryImageData.removeValue(forKey: name)
        if let keys = thumbnailKeysByImageName.removeValue(forKey: name) {
            for key in keys {
                thumbnailCache.removeObject(forKey: key as NSString)
            }
        }
        thumbnailCache.removeObject(forKey: Self.thumbnailCacheKey(forName: name, maxPixelSize: 80) as NSString)
    }

    public func loadPNGData(named fileName: String) -> Data? {
        if let memData = memoryImageData[fileName] {
            return memData
        }
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }

    public func loadPNGDataAsync(named fileName: String) async -> Data? {
        if let memData = memoryImageData[fileName] {
            return memData
        }
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: try? Data(contentsOf: fileURL))
            }
        }
    }
    
    public func deleteImageFile(named name: String) {
        purgeCachedImage(named: name)
        let fileURL = imagesFolderURL.appendingPathComponent(name)
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    public func purgeOrphanedFiles(referencedNames: Set<String>) {
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
    
    // MARK: - Sync Cache & Disk Loaders
    
    public func cachedImage(named fileName: String) -> NSImage? {
        if let mem = memoryImages[fileName] { return mem }
        return imageCache.object(forKey: fileName as NSString)
    }
    
    public func cachedImage(fromFilePath path: String) -> NSImage? {
        imageCache.object(forKey: "file_\(path)" as NSString)
    }
    
    public func loadImage(named fileName: String) -> NSImage? {
        if let mem = memoryImages[fileName] { return mem }
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
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
        if let cached = imageCache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if let img = NSImage(contentsOfFile: path) {
            imageCache.setObject(img, forKey: key, cost: Self.estimatedMemoryCost(of: img))
            return img
        }
        return nil
    }
    
    // MARK: - Async Image & Thumbnail Loaders
    
    public func loadImageAsync(named fileName: String) async -> NSImage? {
        if let cached = cachedImage(named: fileName) { return cached }
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
        if let cached = cachedImage(fromFilePath: path) { return cached }
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
        if let thumb = Self.decodeThumbnail(from: fileURL, maxPixelSize: maxPixelSize) {
            thumbnailCache.setObject(thumb, forKey: key as NSString, cost: Self.estimatedMemoryCost(of: thumb))
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
        if let thumb = Self.decodeThumbnail(from: fileURL, maxPixelSize: maxPixelSize) {
            thumbnailCache.setObject(thumb, forKey: key, cost: Self.estimatedMemoryCost(of: thumb))
            return thumb
        }
        return nil
    }
    
    // MARK: - Background Image Preparation & Helpers
    
    nonisolated public static func prepareImageFromPasteboardData(rawPNG: Data?, rawTIFF: Data?) -> PreparedImage? {
        if let png = rawPNG, let dims = readImagePixelDimensions(from: png) {
            guard dims.width > 2 && dims.height > 2 else { return nil }
            return PreparedImage(pngData: png, width: dims.width, height: dims.height, sha256: sha256Hex(of: png))
        }
        if let tiff = rawTIFF,
           let bitmap = NSBitmapImageRep(data: tiff),
           bitmap.pixelsWide > 2,
           bitmap.pixelsHigh > 2,
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return PreparedImage(pngData: pngData, width: Double(bitmap.pixelsWide), height: Double(bitmap.pixelsHigh), sha256: sha256Hex(of: pngData))
        }
        return nil
    }
    
    nonisolated public static func prepareImageFromFile(path: String) -> PreparedImage? {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "png",
           let data = try? Data(contentsOf: url),
           let dims = readImagePixelDimensions(from: data) {
            guard dims.width > 2 && dims.height > 2 else { return nil }
            return PreparedImage(pngData: data, width: dims.width, height: dims.height, sha256: sha256Hex(of: data))
        }
        
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
           cgImage.width > 2, cgImage.height > 2 {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                return PreparedImage(pngData: pngData, width: Double(cgImage.width), height: Double(cgImage.height), sha256: sha256Hex(of: pngData))
            }
        }
        
        if let img = NSImage(contentsOfFile: path),
           img.size.width > 2, img.size.height > 2,
           let tiff = img.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return PreparedImage(pngData: pngData, width: Double(bitmap.pixelsWide), height: Double(bitmap.pixelsHigh), sha256: sha256Hex(of: pngData))
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
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    
    nonisolated private static func estimatedMemoryCost(of image: NSImage) -> Int {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return max(1, rep.pixelsWide * rep.pixelsHigh * 4)
        }
        return max(1, Int(image.size.width * image.size.height * 4))
    }
    
    nonisolated private static func decodeThumbnail(from fileURL: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        return decodeThumbnail(fromSource: source, maxPixelSize: maxPixelSize)
    }
    
    nonisolated private static func decodeThumbnail(fromData data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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
}
