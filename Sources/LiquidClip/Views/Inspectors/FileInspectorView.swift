/**
 * [INPUT]: 依赖 ClipItem、StorageManager、FinderRevealButton 与 AppKit NSWorkspace
 * [OUTPUT]: 提供文件检查器 FileInspectorView，支持异步图片文件预览卡与访达定位
 * [POS]: Views/Inspectors 文件分支视图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct FileInspectorView: View {
    public let item: ClipItem
    
    public init(item: ClipItem) {
        self.item = item
    }
    
    public var body: some View {
        if let paths = item.filePaths {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(paths, id: \.self) { path in
                    let url = URL(fileURLWithPath: path)
                    let ext = url.pathExtension.lowercased()
                    let isImg = ["png", "jpg", "jpeg", "webp", "gif", "tiff", "tif", "heic", "heif", "svg", "bmp", "ico"].contains(ext)
                    
                    if isImg {
                        AsyncFileImageCard(path: path)
                    } else {
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().lastPathComponent)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            FinderRevealButton(url: url, compact: true)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
}

private struct AsyncFileImageCard: View {
    let path: String
    @State private var image: NSImage?
    
    init(path: String) {
        self.path = path
        _image = State(initialValue: StorageManager.shared.cachedImage(fromFilePath: path))
    }
    
    var body: some View {
        let url = URL(fileURLWithPath: path)
        let resolvedImage = image ?? StorageManager.shared.cachedImage(fromFilePath: path)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let img = resolvedImage {
                    Text("\(Int(img.size.width)) × \(Int(img.size.height))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            if let img = resolvedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 160)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            
            HStack {
                FinderRevealButton(url: url, compact: true)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .task(id: path) {
            if let cached = StorageManager.shared.cachedImage(fromFilePath: path) {
                image = cached
                return
            }
            image = nil
            let loaded = await StorageManager.shared.loadImageAsync(fromFilePath: path)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}
