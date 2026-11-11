import SwiftUI
import AppKit

public struct ClipDetailView: View {
    public let item: ClipItem?
    public let onPaste: () -> Void
    public let onCopy: () -> Void
    public let onTogglePin: () -> Void
    public let onDelete: () -> Void
    
    @State private var copiedNotice: String? = nil
    @State private var showFullText: Bool = false
    private let previewCharacterLimit: Int = 50_000
    
    public init(
        item: ClipItem?,
        onPaste: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onPaste = onPaste
        self.onCopy = onCopy
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }
    
    public var body: some View {
        Group {
            if let item = item {
                VStack(spacing: 0) {
                    // Top Action Bar
                    HStack(spacing: 8) {
                        Button(action: onPaste) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("立即粘贴")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                KeyboardBadge("↵")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .layoutPriority(2)
                        
                        Button(action: onCopy) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                Text("仅复制")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .layoutPriority(1)
                        
                        // Group assignment menu
                        Menu {
                            Section("分组归档 (防删除保护)") {
                                ForEach(StorageManager.shared.groups) { group in
                                    Button(action: {
                                        StorageManager.shared.assignGroup(itemId: item.id, groupId: item.groupId == group.id ? nil : group.id)
                                    }) {
                                        HStack {
                                            Text(group.name)
                                            if item.groupId == group.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            if item.groupId != nil {
                                Divider()
                                Button("移出当前分组") {
                                    StorageManager.shared.assignGroup(itemId: item.id, groupId: nil)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: item.groupId != nil ? "folder.fill" : "folder.badge.plus")
                                    .font(.system(size: 11))
                                if let g = StorageManager.shared.group(for: item.groupId) {
                                    Text(g.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                } else {
                                    Text("加入分组")
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                }
                            }
                            .foregroundColor(item.groupId != nil ? .accentColor : .primary)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(item.groupId != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            .cornerRadius(8)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("将记录加入自定义分组 (分组内容不会被自动清理或清空)")
                        
                        Spacer()
                        
                        Button(action: onTogglePin) {
                            Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                                .font(.system(size: 12))
                                .foregroundColor(item.isPinned ? .orange : .secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "取消收藏" : "收藏")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("删除")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.03))
                    
                    Divider().opacity(0.4)
                    
                    // Selected Item Header Info
                    HStack(spacing: 8) {
                        AppIconView(bundleId: item.sourceAppBundleId, size: 15)
                        Text(item.sourceAppName ?? "剪贴板")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(item.relativeTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        // Group badge
                        if let group = StorageManager.shared.group(for: item.groupId) {
                            HStack(spacing: 3) {
                                Image(systemName: group.icon)
                                    .font(.system(size: 8))
                                Text(group.name)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                        }
                        
                        Text(item.badgeText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    
                    // Main Content Inspector
                    if item.type == .text && !item.isImageFile && item.loadPrimaryImage() == nil {
                        textView(for: item)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                if item.type == .image || item.isImageFile || item.loadPrimaryImage() != nil {
                                    imageView(for: item)
                                } else {
                                    switch item.type {
                                    case .text:
                                        textView(for: item)
                                    case .image:
                                        imageView(for: item)
                                    case .color:
                                        colorView(for: item)
                                    case .url:
                                        urlView(for: item)
                                    case .file:
                                        fileView(for: item)
                                    }
                                }
                            }
                            .padding(14)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("请从左侧选择一条剪贴板记录")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: item?.id) {
            showFullText = false
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    // MARK: - Text Inspector
    @ViewBuilder
    private func textView(for item: ClipItem) -> some View {
        let text = item.plainText ?? ""
        let isOverLimit = text.count > previewCharacterLimit
        let displayText = (isOverLimit && !showFullText) ? String(text.prefix(previewCharacterLimit)) : text
        
        VStack(alignment: .leading, spacing: 10) {
            // Metrics Bar
            HStack(spacing: 12) {
                metricItem(title: "字符数", value: "\(item.charCount)")
                metricItem(title: "词数", value: "\(item.wordCount)")
                metricItem(title: "行数", value: "\(item.lineCount)")
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            
            // Text Transformation Bar (lazy evaluation prevents freezing on large text)
            HStack(spacing: 6) {
                transformButton("大写") { text.uppercased() }
                transformButton("小写") { text.lowercased() }
                transformButton("首字母大写") { text.capitalized }
                transformButton("清除空格") { text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            
            // Large text warning banner if truncated
            if isOverLimit {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(showFullText ? "已加载全部内容（共 \(item.charCount) 字符）" : "文本较长，当前已预览前 \(previewCharacterLimit) 字符（共 \(item.charCount) 字符）。「粘贴」或「复制」仍为完整内容。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if !showFullText {
                        Button("显示全部") {
                            showFullText = true
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            }
            
            // Text Content Display using FastTextEditor (NSTextView)
            FastTextEditor(text: displayText)
                .padding(6)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func metricItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
    
    private func transformButton(_ title: String, transform: @escaping () -> String) -> some View {
        Button(action: {
            let result = transform()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            SoundManager.shared.playCopy()
        }) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Image Inspector (Displays crisp image preview, NEVER shows raw file path)
    @ViewBuilder
    private func imageView(for item: ClipItem) -> some View {
        if let img = item.loadPrimaryImage() {
            let width = item.imageWidth ?? Double(img.size.width)
            let height = item.imageHeight ?? Double(img.size.height)
            
            VStack(alignment: .leading, spacing: 12) {
                // Image Header: Resolution & Format (No ugly file path)
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    
                    Text("分辨率: \(Int(width)) × \(Int(height)) 像素")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    
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
                
                // Image display container
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                    
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 310)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                
                // Export & Finder Actions
                HStack(spacing: 8) {
                    Button(action: {
                        exportImage(img)
                    }) {
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
                    
                    if let path = item.filePaths?.first, FileManager.default.fileExists(atPath: path) {
                        Button(action: {
                            let url = URL(fileURLWithPath: path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                Text("在访达中定位")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func exportImage(_ image: NSImage) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let target = downloads.appendingPathComponent("LiquidClip_\(Int(Date().timeIntervalSince1970)).png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }
    
    // MARK: - Color Inspector
    @ViewBuilder
    private func colorView(for item: ClipItem) -> some View {
        if let hex = item.colorHex {
            let (r, g, b) = ClipItem.hexToRGB(hex)
            let color = Color(red: Double(r)/255.0, green: Double(g)/255.0, blue: Double(b)/255.0)
            
            VStack(spacing: 14) {
                // Large color disc / card
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.4), radius: 10, y: 5)
                
                // Format copiers
                VStack(spacing: 6) {
                    colorCopyRow(label: "HEX", value: hex)
                    colorCopyRow(label: "RGB", value: "rgb(\(r), \(g), \(b))")
                    colorCopyRow(label: "SwiftUI", value: "Color(red: \(String(format: "%.2f", Double(r)/255)), green: \(String(format: "%.2f", Double(g)/255)), blue: \(String(format: "%.2f", Double(b)/255)))")
                }
            }
        }
    }
    
    private func colorCopyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                SoundManager.shared.playCopy()
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - URL Inspector
    @ViewBuilder
    private func urlView(for item: ClipItem) -> some View {
        let raw = item.plainText ?? ""
        let url = URL(string: raw)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundColor(.teal)
                Text(url?.host ?? "网页链接")
                    .font(.system(size: 14, weight: .semibold))
            }
            
            Text(raw)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            
            if let url = url {
                Button(action: {
                    NSWorkspace.shared.open(url)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("在默认浏览器中打开")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.teal)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - File Inspector
    @ViewBuilder
    private func fileView(for item: ClipItem) -> some View {
        if let paths = item.filePaths {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(paths, id: \.self) { path in
                    let url = URL(fileURLWithPath: path)
                    let ext = url.pathExtension.lowercased()
                    let isImg = ["png", "jpg", "jpeg", "webp", "gif", "tiff", "tif", "heic", "heif", "svg", "bmp", "ico"].contains(ext)
                    
                    if isImg, let img = NSImage(contentsOfFile: path) {
                        // Image file preview: Display image, NEVER show path
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(img.size.width)) × \(Int(img.size.height))")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 280)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                            
                            HStack {
                                Button(action: {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                        Text("在访达中定位")
                                    }
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    } else {
                        // Non-image file: Shows filename & location info (never dumps raw path)
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
                            
                            Button(action: {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }) {
                                Text("在访达中显示")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
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

// MARK: - High-performance NSTextView wrapper for large text inspection
public struct FastTextEditor: NSViewRepresentable {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let tv = scrollView.documentView as? NSTextView {
            if tv.string != text {
                tv.string = text
                tv.scroll(NSPoint.zero)
            }
        }
    }
}
