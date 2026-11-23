/**
 * [INPUT]: 依赖 ClipItem、StorageManager 与 OCRService
 * [OUTPUT]: 提供图片内容检查器 ImageInspectorView（异步大图、后台 PNG 导出与 Vision OCR 文字提取）及 FinderRevealButton
 * [POS]: Views/Inspectors 图片分支视图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct ImageInspectorView: View {
    public let item: ClipItem
    public let onCopyText: (String, String) -> Void
    public let onShowToast: (String) -> Void
    
    @State private var image: NSImage?
    @State private var isLoading: Bool = false
    @State private var isRecognizingOCR: Bool = false
    @State private var localOCRText: String?
    
    public init(
        item: ClipItem,
        onCopyText: @escaping (String, String) -> Void,
        onShowToast: @escaping (String) -> Void
    ) {
        self.item = item
        self.onCopyText = onCopyText
        self.onShowToast = onShowToast
        _image = State(initialValue: item.cachedPrimaryImage())
        _localOCRText = State(initialValue: item.ocrText)
    }
    
    public var body: some View {
        let resolvedImage = image ?? item.cachedPrimaryImage()
        let width = item.imageWidth ?? Double(resolvedImage?.size.width ?? 0)
        let height = item.imageHeight ?? Double(resolvedImage?.size.height ?? 0)
        let effectiveOCR = localOCRText ?? item.ocrText
        
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                
                if width > 0 && height > 0 {
                    Text("分辨率: \(Int(width)) × \(Int(height)) 像素")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                } else {
                    Text("剪贴板图片")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                if let first = item.filePaths?.first {
                    let ext = (first as NSString).pathExtension.uppercased()
                    if !ext.isEmpty {
                        Text(ext)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                Spacer()
            }
            
            // Image Preview
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                
                if let img = resolvedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("无法加载图片")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 290)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            
            // Action Buttons
            HStack(spacing: 8) {
                if let img = resolvedImage {
                    Button(action: { exportImage(img) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11))
                            Text("保存到下载文件夹")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { runManualOCR(on: img) }) {
                        HStack(spacing: 5) {
                            if isRecognizingOCR {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 11))
                            }
                            Text(isRecognizingOCR ? "识别中…" : (effectiveOCR == nil ? "提取图片文字 (OCR)" : "重新识别"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRecognizingOCR)
                }
                
                if let path = item.filePaths?.first, FileManager.default.fileExists(atPath: path) {
                    FinderRevealButton(url: URL(fileURLWithPath: path))
                }
            }
            
            // Recognized OCR Text Card
            if let ocrText = effectiveOCR, !ocrText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("识别文字 (支持关键词搜索)", systemImage: "text.viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("复制文字") {
                            onCopyText(ocrText, "已复制图片识别文字")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .buttonStyle(.plain)
                    }
                    
                    Text(ocrText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            }
        }
        .task(id: item.id) {
            localOCRText = item.ocrText
            isRecognizingOCR = false
            if let cached = item.cachedPrimaryImage() {
                image = cached
                isLoading = false
                return
            }
            image = nil
            isLoading = true
            let loaded = await item.loadPrimaryImageAsync()
            if !Task.isCancelled {
                image = loaded
                isLoading = false
            }
        }
    }
    
    private func runManualOCR(on image: NSImage) {
        isRecognizingOCR = true
        let targetId = item.id
        Task {
            let text = await OCRService.recognizeText(from: image)
            await MainActor.run {
                isRecognizingOCR = false
                if let text = text, !text.isEmpty {
                    localOCRText = text
                    StorageManager.shared.updateOCRText(id: targetId, text: text)
                    onShowToast("已识别文字并加入搜索索引")
                } else {
                    onShowToast("未在图片中识别到可读文字")
                }
            }
        }
    }
    
    private func exportImage(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let target = downloads.appendingPathComponent("LiquidClip_\(Int(Date().timeIntervalSince1970)).png")
        let toastCallback = onShowToast
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let rep = NSBitmapImageRep(data: tiffData),
                  let png = rep.representation(using: .png, properties: [:]) else {
                return
            }
            do {
                try png.write(to: target, options: .atomic)
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([target])
                    toastCallback("已保存到下载文件夹")
                }
            } catch {
                print("Failed to export image: \(error)")
            }
        }
    }
}

public struct FinderRevealButton: View {
    public let url: URL
    public var compact: Bool
    
    public init(url: URL, compact: Bool = false) {
        self.url = url
        self.compact = compact
    }
    
    public var body: some View {
        Button(action: {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }) {
            HStack(spacing: compact ? 4 : 5) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                Text("在访达中定位")
                    .font(.system(size: 11, weight: compact ? .regular : .medium))
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
