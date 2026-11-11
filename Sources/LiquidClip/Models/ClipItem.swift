import Foundation
import SwiftUI
import AppKit

public struct ClipItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public var type: ClipType
    public var plainText: String?
    public var htmlText: String?
    public var imageFileName: String?
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
    
    public init(
        id: UUID = UUID(),
        type: ClipType,
        plainText: String? = nil,
        htmlText: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Double? = nil,
        imageHeight: Double? = nil,
        filePaths: [String]? = nil,
        colorHex: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        isPinned: Bool = false,
        groupId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.plainText = plainText
        self.htmlText = htmlText
        self.imageFileName = imageFileName
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
    }
    
    // Hashable conformance based on ID
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // Content hash for duplicate detection
    public var contentFingerprint: String {
        switch type {
        case .text, .color, .url:
            return plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .image:
            return imageFileName ?? "\(imageWidth ?? 0)x\(imageHeight ?? 0)"
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
    
    // Attempt to load the primary display image
    @MainActor
    public func loadPrimaryImage() -> NSImage? {
        if let name = imageFileName, let img = StorageManager.shared.loadImage(named: name) {
            return img
        }
        if let path = filePaths?.first, isImageFile {
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        // Also check if plainText is an existing image file path (must be short single-line path)
        if let text = plainText, text.count < 1024, !text.contains("\n") {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "file://", with: "")
            if clean.hasPrefix("/") {
                let ext = (clean as NSString).pathExtension.lowercased()
                let imageExts = ["png", "jpg", "jpeg", "webp", "gif", "tiff", "tif", "heic", "heif", "svg", "bmp"]
                if imageExts.contains(ext), FileManager.default.fileExists(atPath: clean) {
                    return NSImage(contentsOfFile: clean)
                }
            }
        }
        return nil
    }

    // Display Title
    public var displayTitle: String {
        switch type {
        case .text:
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
                let (r, g, b) = ClipItem.hexToRGB(hex)
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
        plainText?.count ?? 0
    }
    
    public var lineCount: Int {
        guard let text = plainText, !text.isEmpty else { return 0 }
        var count = 1
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                count += 1
            }
        }
        return count
    }
    
    public var wordCount: Int {
        guard let text = plainText, !text.isEmpty else { return 0 }
        var count = 0
        var inWord = false
        let whitespace = CharacterSet.whitespacesAndNewlines
        for scalar in text.unicodeScalars {
            if whitespace.contains(scalar) {
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }
    
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
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: createdAt)
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
    
    // Helper to convert hex to RGB ints
    public static func hexToRGB(_ hex: String) -> (Int, Int, Int) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        var rgbValue: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgbValue)
        
        if clean.count == 6 {
            let r = Int((rgbValue & 0xFF0000) >> 16)
            let g = Int((rgbValue & 0x00FF00) >> 8)
            let b = Int(rgbValue & 0x0000FF)
            return (r, g, b)
        } else if clean.count == 3 {
            let r = Int((rgbValue & 0xF00) >> 8) * 17
            let g = Int((rgbValue & 0x0F0) >> 4) * 17
            let b = Int(rgbValue & 0x00F) * 17
            return (r, g, b)
        }
        return (0, 0, 0)
    }
}
