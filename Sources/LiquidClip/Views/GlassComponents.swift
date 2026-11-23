/**
 * [INPUT]: 依赖 SwiftUI 与 AppKit NSWorkspace 图标能力
 * [OUTPUT]: 提供 AppIconCache、FileIconCache、AppIconView、KeyboardBadge、LiquidSearchBar 与 GlassIconButton 组件
 * [POS]: 通用液态玻璃基础 UI 组件库，供 MainWindowView、ClipRowView 与 ClipDetailView 复用
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

// MARK: - In-Memory App & File Icon Caches
// Prevents high-overhead synchronous IPC calls to LaunchServices and IconServices on every view pass
public final class AppIconCache {
    public static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 150
    }
    
    public func icon(for bundleId: String?) -> NSImage? {
        guard let bundleId = bundleId, !bundleId.isEmpty else { return nil }
        let key = bundleId as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            cache.setObject(icon, forKey: key)
            return icon
        }
        return nil
    }
}

public final class FileIconCache {
    public static let shared = FileIconCache()
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 150
    }
    
    public func icon(for path: String) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = (ext.isEmpty ? (path as NSString).lastPathComponent : ext) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

// Displays macOS application icon from Bundle Identifier (Instant O(1) Cache)
public struct AppIconView: View {
    public let bundleId: String?
    public let size: CGFloat
    
    public init(bundleId: String?, size: CGFloat = 16) {
        self.bundleId = bundleId
        self.size = size
    }
    
    public var body: some View {
        Group {
            if let icon = AppIconCache.shared.icon(for: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(size * 0.22)
    }
}

// Sleek liquid glass keyboard badge
public struct KeyboardBadge: View {
    public let text: String
    public var isHighlighted: Bool = false
    
    public init(_ text: String, isHighlighted: Bool = false) {
        self.text = text
        self.isHighlighted = isHighlighted
    }
    
    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(isHighlighted ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// Translucent Liquid Search Bar
public struct LiquidSearchBar: View {
    @Binding public var text: String
    public var focusTrigger: Int
    @FocusState private var isFocused: Bool
    
    public init(text: Binding<String>, focusTrigger: Int = 0) {
        self._text = text
        self.focusTrigger = focusTrigger
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(text.isEmpty ? .secondary : .primary)
            
            TextField("搜索剪贴板历史 (输入关键字、应用名或颜色)...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .onAppear {
            isFocused = true
        }
        .onChange(of: focusTrigger) {
            isFocused = true
        }
    }
}

// Glass Icon Button with liquid hover
public struct GlassIconButton: View {
    public let icon: String
    public var title: String? = nil
    public var color: Color = .primary
    public var size: CGFloat = 28
    public var action: () -> Void
    
    @State private var isHovered = false
    
    public init(
        icon: String,
        title: String? = nil,
        color: Color = .primary,
        size: CGFloat = 28,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.color = color
        self.size = size
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.44, weight: .medium))
                if let title = title {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(color)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, title != nil ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.2 : 0.08), lineWidth: 0.5)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// Responsive wrapping flow layout for action chips
public struct FlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    
    public init(horizontalSpacing: CGFloat = 6, verticalSpacing: CGFloat = 6) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let result = layoutRows(maxWidth: maxWidth, subviews: subviews)
        let width = proposal.width ?? result.maxLineWidth
        return CGSize(width: width, height: result.totalHeight)
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in result.rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }
    
    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }
    
    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    
    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> (rows: [Row], maxLineWidth: CGFloat, totalHeight: CGFloat) {
        var rows: [Row] = []
        var current = Row()
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = current.items.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if !current.items.isEmpty && neededWidth > maxWidth {
                rows.append(current)
                current = Row(items: [RowItem(subview: subview, size: size)], width: size.width, height: size.height)
            } else {
                current.items.append(RowItem(subview: subview, size: size))
                current.width = neededWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        
        let maxLineWidth = rows.map(\.width).max() ?? 0
        let totalHeight: CGFloat = rows.isEmpty
            ? 0
            : rows.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return (rows, maxLineWidth, totalHeight)
    }
}
