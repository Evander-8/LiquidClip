/**
 * [INPUT]: 依赖 Foundation / SwiftUI / AppKit 基础类型，以及同层 ClipType 与 StorageManager 异步/缓存图像接口
 * [OUTPUT]: 提供 ClipItem 剪贴板记录模型、预计算文本统计、内容指纹、RGBA 颜色解析及图像缓存/异步读取桥接
 * [POS]: 核心数据实体，被 StorageManager 持久化与管理，并直接驱动列表行 ClipRowView 与详情页 ClipDetailView
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import SwiftUI
import AppKit

public struct ClipItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public var type: ClipType
    public var plainText: String? {
        didSet {
            refreshCachedMetrics()
        }
    }
    public var htmlText: String?
    public var imageFileName: String?
    public var imageHash: String?
    public var imageWidth: Double?
    public var imageHeight: Double?
    public var filePaths: [String]?
    public var colorHex: String?
    public var sourceAppName: String?
    public var sourceAppBundleId: String?
    public var isPinned: Bool
    public var groupId: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var cachedCharCount: Int?
    public var cachedLineCount: Int?
    public var cachedWordCount: Int?
    public var cachedDisplayTitle: String?
    
    public init(
        id: UUID = UUID(),
        type: ClipType,
        plainText: String? = nil,
        htmlText: String? = nil,
        imageFileName: String? = nil,
        imageHash: String? = nil,
        imageWidth: Double? = nil,
        imageHeight: Double? = nil,
        filePaths: [String]? = nil,
        colorHex: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        isPinned: Bool = false,
        groupId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        cachedCharCount: Int? = nil,
        cachedLineCount: Int? = nil,
        cachedWordCount: Int? = nil,
        cachedDisplayTitle: String? = nil
    ) {
        self.id = id
        self.type = type
        self.plainText = plainText
        self.htmlText = htmlText
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.colorHex = colorHex
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.isPinned = isPinned
        self.groupId = groupId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cachedCharCount = cachedCharCount
        self.cachedLineCount = cachedLineCount
        self.cachedWordCount = cachedWordCount
        self.cachedDisplayTitle = cachedDisplayTitle
        self.populateCachedMetricsIfNeeded()
    }
    
    // Hashable conformance based on ID
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // Recompute cached text metrics when plainText mutates
    private mutating func refreshCachedMetrics() {
        if let text = plainText {
            cachedCharCount = text.count
            cachedLineCount = Self.computeLineCount(for: text)
            cachedWordCount = Self.computeWordCount(for: text)
        } else {
            cachedCharCount = nil
            cachedLineCount = nil
            cachedWordCount = nil
        }
        if type == .text {
            cachedDisplayTitle = Self.computeTextDisplayTitle(from: plainText)
        } else {
            cachedDisplayTitle = nil
        }
    }
    
    // Backfill cached metrics for legacy JSON records loaded from disk
    public mutating func populateCachedMetricsIfNeeded() {
        if let text = plainText {
            if cachedCharCount == nil {
                cachedCharCount = text.count
            }
            if cachedLineCount == nil {
                cachedLineCount = Self.computeLineCount(for: text)
            }
            if cachedWordCount == nil {
                cachedWordCount = Self.computeWordCount(for: text)
            }
        }
        if type == .text && cachedDisplayTitle == nil {
            cachedDisplayTitle = Self.computeTextDisplayTitle(from: plainText)
        }
    }
    
    // Content hash for duplicate detection
    public var contentFingerprint: String {
        switch type {
        case .text, .color, .url:
            return plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .image:
            return imageHash ?? imageFileName ?? "\(imageWidth ?? 0)x\(imageHeight ?? 0)"
        case .file:
            return (filePaths ?? []).joined(separator: "|")
        }
    }
    
    // Check if item contains an image (either pure image or an image file)
    public var isImageFile: Bool {
        guard let path = filePaths?.first, filePaths?.count == 1 else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        let imageExts = ["png", "jpg", "jpeg", "webp", "gif", "tiff", "tif", "heic", "heif", "svg", "bmp", "ico"]
        return imageExts.contains(ext)
    }
    
    // Pure in-memory cache lookup (zero disk I/O)
    @MainActor
    public func cachedThumbnail(maxPixelSize: CGFloat = 80) -> NSImage? {
        if let name = imageFileName {
            return StorageManager.shared.cachedThumbnail(named: name, maxPixelSize: maxPixelSize)
        }
        if let path = filePaths?.first, isImageFile {
            return StorageManager.shared.cachedThumbnail(forFilePath: path, maxPixelSize: maxPixelSize)
        }
        return nil
    }
    
    // Async thumbnail loading for row lists
    @MainActor
    public func loadThumbnailAsync(maxPixelSize: CGFloat = 80) async -> NSImage? {
        if let name = imageFileName {
            return await StorageManager.shared.loadThumbnailAsync(named: name, maxPixelSize: maxPixelSize)
        }
        if let path = filePaths?.first, isImageFile {
            return await StorageManager.shared.loadThumbnailAsync(forFilePath: path, maxPixelSize: maxPixelSize)
        }
        return nil
    }
    
    // Fast downscaled thumbnail loading for row lists
    @MainActor
    public func loadThumbnail(maxPixelSize: CGFloat = 80) -> NSImage? {
        if let name = imageFileName {
            return StorageManager.shared.loadThumbnail(named: name, maxPixelSize: maxPixelSize)
        }
        if let path = filePaths?.first, isImageFile {
            return StorageManager.shared.loadThumbnail(forFilePath: path, maxPixelSize: maxPixelSize)
        }
        return nil
    }
    
    // Pure in-memory cache lookup for primary display image
    @MainActor
    public func cachedPrimaryImage() -> NSImage? {
        if let name = imageFileName {
            return StorageManager.shared.cachedImage(named: name)
        }
        if let path = filePaths?.first, isImageFile {
            return StorageManager.shared.cachedImage(fromFilePath: path)
        }
        return nil
    }
    
    // Async primary display image loading
    @MainActor
    public func loadPrimaryImageAsync() async -> NSImage? {
        if let name = imageFileName {
            return await StorageManager.shared.loadImageAsync(named: name)
        }
        if let path = filePaths?.first, isImageFile {
            return await StorageManager.shared.loadImageAsync(fromFilePath: path)
        }
        return nil
    }
    
    // Attempt to load the primary display image (cached in StorageManager)
    @MainActor
    public func loadPrimaryImage() -> NSImage? {
        if let name = imageFileName {
            return StorageManager.shared.loadImage(named: name)
        }
        if let path = filePaths?.first, isImageFile {
            return StorageManager.shared.loadImage(fromFilePath: path)
        }
        return nil
    }

    // Display Title
    public var displayTitle: String {
        switch type {
        case .text:
            return cachedDisplayTitle ?? Self.computeTextDisplayTitle(from: plainText)
            
        case .color:
            return colorHex ?? (plainText ?? "未知颜色")
            
        case .url:
            if let text = plainText, let url = URL(string: text) {
                let host = url.host ?? ""
                let path = url.path.isEmpty || url.path == "/" ? "" : url.path
                return host.isEmpty ? text : "\(host)\(path)"
            }
            return plainText ?? "网页链接"
            
        case .file:
            if let paths = filePaths, !paths.isEmpty {
                if paths.count == 1 {
                    let path = paths[0]
                    if isImageFile {
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        return name.isEmpty ? "图片" : name
                    }
                    return URL(fileURLWithPath: path).lastPathComponent
                } else {
                    return "\(URL(fileURLWithPath: paths[0]).lastPathComponent) 等 \(paths.count) 个文件"
                }
            }
            return "文件"
            
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "图片 (\(Int(w)) × \(Int(h)))"
            }
            return "图片"
        }
    }
    
    // Secondary description / preview
    public var previewSnippet: String {
        switch type {
        case .text:
            guard let text = plainText, !text.isEmpty else { return "" }
            let sample = text.prefix(1000)
            let lines = sample.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if lines.count > 1 {
                return lines.dropFirst().prefix(2).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }
            return text.count > 80 ? String(text.prefix(80)) + "..." : text
            
        case .color:
            if let hex = colorHex {
                let (r, g, b, a) = ClipItem.hexToRGBA(hex)
                if a < 1.0 {
                    return String(format: "RGBA(%d, %d, %d, %.2f)", r, g, b, a)
                }
                return "RGB(\(r), \(g), \(b))"
            }
            return ""
            
        case .url:
            return plainText ?? ""
            
        case .file:
            if let paths = filePaths, !paths.isEmpty {
                if isImageFile {
                    if let w = imageWidth, let h = imageHeight {
                        return "\(Int(w)) × \(Int(h)) 像素"
                    }
                    return "图片文件"
                }
                return paths[0]
            }
            return ""
            
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "\(Int(w)) × \(Int(h)) 像素"
            }
            return "剪贴板图片"
        }
    }
    
    // Badge info (e.g. "128 字", "3 行", "1.2 MB")
    public var badgeText: String {
        switch type {
        case .text:
            let count = charCount
            if lineCount > 1 {
                return "\(count) 字 · \(lineCount) 行"
            }
            return "\(count) 字符"
            
        case .color:
            return "HEX"
            
        case .url:
            return "URL"
            
        case .file:
            if isImageFile {
                let ext = (filePaths?.first as NSString?)?.pathExtension.uppercased() ?? "IMG"
                return ext.isEmpty ? "图片" : ext
            }
            let count = filePaths?.count ?? 0
            return count > 1 ? "\(count) 个项目" : "文件"
            
        case .image:
            return "PNG"
        }
    }
    
    public var charCount: Int {
        cachedCharCount ?? (plainText?.count ?? 0)
    }
    
    public var lineCount: Int {
        if let cached = cachedLineCount { return cached }
        guard let text = plainText, !text.isEmpty else { return 0 }
        return Self.computeLineCount(for: text)
    }
    
    public var wordCount: Int {
        if let cached = cachedWordCount { return cached }
        guard let text = plainText, !text.isEmpty else { return 0 }
        return Self.computeWordCount(for: text)
    }
    
    private static func computeTextDisplayTitle(from plainText: String?) -> String {
        guard let text = plainText, !text.isEmpty else { return "空白文本" }
        var startIdx = text.startIndex
        while startIdx < text.endIndex && (text[startIdx].isWhitespace || text[startIdx].isNewline) {
            startIdx = text.index(after: startIdx)
        }
        if startIdx == text.endIndex { return "空白文本" }
        
        var endIdx = startIdx
        var count = 0
        while endIdx < text.endIndex && !text[endIdx].isNewline && count < 200 {
            endIdx = text.index(after: endIdx)
            count += 1
        }
        let title = String(text[startIdx..<endIdx]).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "空白文本" : title
    }
    
    private static func computeLineCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 1
        for byte in text.utf8 where byte == 0x0A {
            count += 1
        }
        return count
    }
    
    private static func computeWordCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var inWord = false
        let whitespace = CharacterSet.whitespacesAndNewlines
        for scalar in text.unicodeScalars {
            let isSpace: Bool
            if scalar.value <= 0x7F {
                isSpace = scalar.value == 0x20 || scalar.value == 0x0A || scalar.value == 0x0D ||
                          scalar.value == 0x09 || scalar.value == 0x0B || scalar.value == 0x0C
            } else {
                isSpace = whitespace.contains(scalar)
            }
            if isSpace {
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }
    
    // Shared reusable date formatter to avoid expensive per-frame instantiation
    private static let mmDdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }()
    
    // Relative human-readable time
    public var relativeTime: String {
        let now = Date()
        let interval = now.timeIntervalSince(createdAt)
        
        if interval < 10 {
            return "刚刚"
        } else if interval < 60 {
            return "\(Int(interval))秒前"
        } else if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else if interval < 86400 * 2 {
            return "昨天"
        } else if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return "\(days)天前"
        } else {
            return Self.mmDdFormatter.string(from: createdAt)
        }
    }
    
    // Search filter matching
    public func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        
        if let text = plainText, text.localizedCaseInsensitiveContains(q) {
            return true
        }
        if let app = sourceAppName, app.localizedCaseInsensitiveContains(q) {
            return true
        }
        if let hex = colorHex, hex.localizedCaseInsensitiveContains(q) {
            return true
        }
        if let paths = filePaths {
            for p in paths {
                if (p as NSString).lastPathComponent.localizedCaseInsensitiveContains(q) {
                    return true
                }
            }
        }
        return false
    }
    
    // Helper to convert hex (3, 6, or 8 digits) to RGBA tuple
    public static func hexToRGBA(_ hex: String) -> (Int, Int, Int, Double) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard let value = UInt64(clean, radix: 16) else {
            return (0, 0, 0, 1.0)
        }
        
        if clean.count == 8 {
            let r = Int((value & 0xFF000000) >> 24)
            let g = Int((value & 0x00FF0000) >> 16)
            let b = Int((value & 0x0000FF00) >> 8)
            let a = Double(value & 0x000000FF) / 255.0
            return (r, g, b, a)
        } else if clean.count == 6 {
            let r = Int((value & 0xFF0000) >> 16)
            let g = Int((value & 0x00FF00) >> 8)
            let b = Int(value & 0x0000FF)
            return (r, g, b, 1.0)
        } else if clean.count == 3 {
            let r = Int((value & 0xF00) >> 8) * 17
            let g = Int((value & 0x0F0) >> 4) * 17
            let b = Int(value & 0x00F) * 17
            return (r, g, b, 1.0)
        }
        return (0, 0, 0, 1.0)
    }
    
    // Helper to convert hex to RGB ints
    public static func hexToRGB(_ hex: String) -> (Int, Int, Int) {
        let (r, g, b, _) = hexToRGBA(hex)
        return (r, g, b)
    }
}
