/**
 * [INPUT]: 依赖 ClipItem、TextTransformTools（CoreImage 二维码）与 AppKit NSWorkspace
 * [OUTPUT]: 提供链接检查器 URLInspectorView，含浏览器打开、Query 参数解析与扫码二维码展示
 * [POS]: Views/Inspectors 链接分支视图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct URLInspectorView: View {
    public let item: ClipItem
    public let onCopyText: (String, String) -> Void
    
    @State private var showQRCode: Bool = true
    
    public init(item: ClipItem, onCopyText: @escaping (String, String) -> Void) {
        self.item = item
        self.onCopyText = onCopyText
    }
    
    public var body: some View {
        let raw = item.plainText ?? ""
        let url = URL(string: raw)
        let queryItems = TextTransformTools.extractURLQueryItems(from: raw)
        
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
            
            HStack(spacing: 8) {
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
                
                Button(action: { showQRCode.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                        Text(showQRCode ? "收起二维码" : "生成二维码")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            if showQRCode, let qrImage = TextTransformTools.generateQRCodeImage(from: raw, size: 132) {
                HStack(spacing: 12) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 112, height: 112)
                        .padding(6)
                        .background(Color.white)
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("手机扫码打开")
                            .font(.system(size: 12, weight: .semibold))
                        Text("使用相机或微信扫描即可直接在移动端打开此链接。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
            
            if !queryItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Query 参数 (\(queryItems.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(queryItems.enumerated()), id: \.offset) { _, param in
                        HStack(spacing: 8) {
                            Text(param.name)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.teal)
                            Text(param.value ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            if let val = param.value, !val.isEmpty {
                                Button(action: {
                                    onCopyText(val, "已复制参数 \(param.name)")
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(5)
                    }
                }
            }
        }
    }
}
