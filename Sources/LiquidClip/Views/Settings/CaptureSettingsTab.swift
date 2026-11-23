/**
 * [INPUT]: 依赖 AppSettings、ClipboardMonitor、PasteSimulator 与 SettingsComponents
 * [OUTPUT]: 提供「粘贴与采集」设置分栏视图 CaptureSettingsTab（辅助功能权限检测/修复、自动粘贴、划词复制与离线 OCR）
 * [POS]: SettingsView 的粘贴与采集分类子页
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI

public struct CaptureSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    public let isAccessibilityGranted: Bool
    
    public init(isAccessibilityGranted: Bool) {
        self.isAccessibilityGranted = isAccessibilityGranted
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroupCard(
                title: "系统辅助功能权限",
                footer: isAccessibilityGranted
                    ? nil
                    : "本地重新编译或升级后若系统开关已亮但仍显示未授权，可点击「修复授权」一键重置 TCC 记录。"
            ) {
                HStack(spacing: 10) {
                    SettingsIconBadge(
                        systemName: isAccessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill",
                        color: isAccessibilityGranted ? .green : .orange
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动粘贴权限 (Accessibility)")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(isAccessibilityGranted ? "已获得授权，选中历史记录可直接向当前窗口注入 ⌘V。" : "未获得授权。选中记录时将仅复制至剪贴板，需手动按键粘贴。")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer(minLength: 8)
                    
                    if isAccessibilityGranted {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("已授权")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Button("修复授权") {
                                PasteSimulator.shared.repairAccessibilityTrust()
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)
                            .buttonStyle(.plain)
                            .help("重置旧的签名授权并重新弹出系统授权提示")
                            
                            Button("去授权") {
                                PasteSimulator.shared.openAccessibilitySettings()
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .cornerRadius(6)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            
            SettingsGroupCard(title: "采集与智能识别") {
                SettingsToggleRow(
                    icon: "arrow.right.doc.on.clipboard",
                    iconColor: .blue,
                    title: "选中历史项时自动粘贴 (⌘V)",
                    subtitle: "关闭时仅将条目放回剪贴板；支持在详情中用 ⇧↵ 进行纯文本粘贴",
                    isOn: $settings.autoPasteOnSelect
                )
                
                SettingsRowDivider()
                
                SettingsToggleRow(
                    icon: "cursorarrow.click.2",
                    iconColor: .teal,
                    title: "划词自动复制 (划选文本即记录)",
                    subtitle: "关闭时忽略终端（Ghostty/iTerm 等）的划选抓取，仅在按下 ⌘C 时才记录",
                    isOn: $settings.enableSelectionCopy
                )
                .onChange(of: settings.enableSelectionCopy) {
                    ClipboardMonitor.shared.setupMouseSelectionMonitor()
                }
                
                SettingsRowDivider()
                
                SettingsToggleRow(
                    icon: "text.viewfinder",
                    iconColor: .purple,
                    title: "自动识别图片文字 (离线 OCR 搜图)",
                    subtitle: "基于系统原生 Vision 框架在本地后台识图并加入 FTS5 检索索引",
                    isOn: $settings.enableAutoOCR
                )
            }
        }
    }
}
