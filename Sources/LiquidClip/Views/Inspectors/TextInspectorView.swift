/**
 * [INPUT]: 依赖 ClipItem、TextTransformTools 与 AppKit NSTextView
 * [OUTPUT]: 提供文本内容检查器 TextInspectorView 与高性能非连续排版编辑器 FastTextEditor
 * [POS]: Views/Inspectors 文本分支视图，提供统计、时间戳识别与 JSON/URL/Base64/大小写转换工具栏
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct TextInspectorView: View {
    public let item: ClipItem
    @Binding public var showFullText: Bool
    public let onCopyText: (String, String) -> Void
    
    private let previewCharacterLimit: Int = 50_000
    
    public init(
        item: ClipItem,
        showFullText: Binding<Bool>,
        onCopyText: @escaping (String, String) -> Void
    ) {
        self.item = item
        self._showFullText = showFullText
        self.onCopyText = onCopyText
    }
    
    public var body: some View {
        let text = item.plainText ?? ""
        let isOverLimit = text.count > previewCharacterLimit
        let displayText = (isOverLimit && !showFullText) ? String(text.prefix(previewCharacterLimit)) : text
        let timestampMatch = TextTransformTools.parseUnixTimestamp(text)
        let isJSONCandidate = text.count <= 200_000 && TextTransformTools.prettyFormatJSON(text) != nil
        
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
            
            // Unix Timestamp quick detection card
            if let ts = timestampMatch {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.teal)
                    Text("时间戳:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(ts.local)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    Button("复制本地时间") {
                        onCopyText(ts.local, "已复制时间: \(ts.local)")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.teal)
                    .buttonStyle(.plain)
                    
                    Button("ISO8601") {
                        onCopyText(ts.iso8601, "已复制 ISO 时间")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.teal.opacity(0.08))
                .cornerRadius(6)
            }
            
            // Text & Developer Transformation Bar (auto-wrapping flow layout)
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                transformButton("大写") { text.uppercased() }
                transformButton("小写") { text.lowercased() }
                transformButton("首字母大写") { text.capitalized }
                transformButton("清除空格") { text.trimmingCharacters(in: .whitespacesAndNewlines) }
                
                if isJSONCandidate {
                    transformButton("JSON 美化") { TextTransformTools.prettyFormatJSON(text) ?? text }
                    transformButton("JSON 压缩") { TextTransformTools.minifyJSON(text) ?? text }
                }
                
                transformButton("URL 编码") { TextTransformTools.urlEncode(text) ?? text }
                if let decodedURL = TextTransformTools.urlDecode(text), decodedURL != text {
                    transformButton("URL 解码") { decodedURL }
                }
                transformButton("Base64 编码") { TextTransformTools.base64Encode(text) }
                if let decodedB64 = TextTransformTools.base64Decode(text) {
                    transformButton("Base64 解码") { decodedB64 }
                }
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
            onCopyText(result, "已复制「\(title)」结果")
        }) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
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
