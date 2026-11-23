/**
 * [INPUT]: 依赖 ClipItem（hexToRGBA）
 * [OUTPUT]: 提供色彩预览与 HEX/RGB/RGBA/SwiftUI 代码复制视图 ColorInspectorView
 * [POS]: Views/Inspectors 颜色分支视图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI

public struct ColorInspectorView: View {
    public let item: ClipItem
    public let onCopyText: (String, String) -> Void
    
    public init(item: ClipItem, onCopyText: @escaping (String, String) -> Void) {
        self.item = item
        self.onCopyText = onCopyText
    }
    
    public var body: some View {
        if let hex = item.colorHex {
            let (r, g, b, a) = ClipItem.hexToRGBA(hex)
            let color = Color(red: Double(r)/255.0, green: Double(g)/255.0, blue: Double(b)/255.0, opacity: a)
            
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.4), radius: 10, y: 5)
                
                VStack(spacing: 6) {
                    colorCopyRow(label: "HEX", value: hex)
                    colorCopyRow(label: "RGB", value: "rgb(\(r), \(g), \(b))")
                    if a < 1.0 {
                        colorCopyRow(label: "RGBA", value: String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, a))
                        colorCopyRow(label: "SwiftUI", value: String(format: "Color(red: %.2f, green: %.2f, blue: %.2f, opacity: %.2f)", Double(r)/255, Double(g)/255, Double(b)/255, a))
                    } else {
                        colorCopyRow(label: "SwiftUI", value: "Color(red: \(String(format: "%.2f", Double(r)/255)), green: \(String(format: "%.2f", Double(g)/255)), blue: \(String(format: "%.2f", Double(b)/255)))")
                    }
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
                onCopyText(value, "已复制 \(label): \(value)")
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
}
