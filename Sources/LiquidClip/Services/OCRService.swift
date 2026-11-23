/**
 * [INPUT]: 依赖系统原生 Vision 框架与 AppKit NSImage
 * [OUTPUT]: 提供离线中英文图片文字识别服务 OCRService.recognizeText(from:)
 * [POS]: 零第三方依赖的视觉文本提取引擎，供 StorageManager 后台索引与 ImageInspectorView 手动提取调用
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit
import Vision

public enum OCRService {
    private static let ocrQueue = DispatchQueue(label: "com.liquidclip.ocr", qos: .utility)
    
    /// Performs on-device text recognition on an NSImage (Chinese + English).
    public static func recognizeText(from image: NSImage) async -> String? {
        guard let cgImage = extractCGImage(from: image) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            ocrQueue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let result = lines.joined(separator: "\n")
                    continuation.resume(returning: result.isEmpty ? nil : result)
                } catch {
                    print("OCR recognition failed: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private static func extractCGImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.cgImage
        }
        return nil
    }
}
