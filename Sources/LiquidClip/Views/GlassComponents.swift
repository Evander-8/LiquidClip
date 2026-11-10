import SwiftUI
import AppKit

// Displays macOS application icon from Bundle Identifier
public struct AppIconView: View {
    public let bundleId: String?
    public let size: CGFloat
    
    public init(bundleId: String?, size: CGFloat = 16) {
        self.bundleId = bundleId
        self.size = size
    }
    
    private var appIcon: NSImage? {
        guard let bundleId = bundleId, !bundleId.isEmpty else { return nil }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }
    
    public var body: some View {
        Group {
            if let icon = appIcon {
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
    @FocusState private var isFocused: Bool
    
    public init(text: Binding<String>) {
        self._text = text
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
