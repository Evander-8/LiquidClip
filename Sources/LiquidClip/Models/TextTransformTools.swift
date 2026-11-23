/**
 * [INPUT]: 依赖 Foundation、AppKit 与 CoreImage（CIQRCodeGenerator）
 * [OUTPUT]: 提供 JSON 格式化/压缩、URL 编解码、Base64 编解码、Unix 时间戳解析与原生二维码生成工具
 * [POS]: 纯函数开发者/设计微型工具箱，供文本与链接 Inspector 视图调用及单元测试
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit
import CoreImage

public enum TextTransformTools {
    
    // MARK: - JSON Formatting & Minifying
    
    public static func prettyFormatJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: formatted, encoding: .utf8)
    }
    
    public static func minifyJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let minified = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: minified, encoding: .utf8)
    }
    
    // MARK: - URL Encode / Decode
    
    public static func urlEncode(_ text: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return text.addingPercentEncoding(withAllowedCharacters: allowed)
    }
    
    public static func urlDecode(_ text: String) -> String? {
        text.removingPercentEncoding
    }
    
    // MARK: - Base64 Encode / Decode
    
    public static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }
    
    public static func base64Decode(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Unix Timestamp Detection (Seconds & Milliseconds, Year 2000–2100)
    
    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    public static func parseUnixTimestamp(_ text: String) -> (local: String, iso8601: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10 || trimmed.count == 13,
              trimmed.allSatisfy(\.isASCII),
              trimmed.allSatisfy(\.isNumber),
              let raw = Double(trimmed) else {
            return nil
        }
        let seconds = trimmed.count == 13 ? raw / 1000.0 : raw
        // Year 2000-01-01 (946684800) to Year 2100-01-01 (4102444800)
        guard seconds >= 946_684_800 && seconds <= 4_102_444_800 else {
            return nil
        }
        let date = Date(timeIntervalSince1970: seconds)
        return (localDateFormatter.string(from: date), isoFormatter.string(from: date))
    }
    
    // MARK: - Native CoreImage QR Code Generation
    
    public static func generateQRCodeImage(from text: String, size: CGFloat = 160) -> NSImage? {
        guard !text.isEmpty,
              let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        let extent = outputImage.extent
        guard extent.width > 0 && extent.height > 0 else { return nil }
        
        let scale = max(1.0, min(size / extent.width, size / extent.height))
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let context = CIContext()
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        }
        let rep = NSCIImageRep(ciImage: transformed)
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
