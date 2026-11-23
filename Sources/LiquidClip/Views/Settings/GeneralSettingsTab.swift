/**
 * [INPUT]: 依赖 AppSettings 与 SettingsComponents 原语
 * [OUTPUT]: 提供「通用」设置分栏视图 GeneralSettingsTab（全局快捷键、开机自启、窗口位置、角标与音效）
 * [POS]: SettingsView 的通用分类子页
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI

public struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroupCard(title: "呼出与快捷键") {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "command", color: .blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全局呼出快捷键")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("在任意应用中按下即可瞬间唤起或隐藏主窗口")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 8)
                    HotkeyRecorderPill()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                
                SettingsRowDivider()
                
                SettingsToggleRow(
                    icon: "display",
                    iconColor: .indigo,
                    title: "呼出窗口跟随鼠标所在屏幕",
                    subtitle: "多显示器环境下优先定位至光标所在的屏幕居中显示",
                    isOn: $settings.windowFollowsCursor
                )
            }
            
            SettingsGroupCard(title: "启动与界面交互") {
                SettingsToggleRow(
                    icon: "power",
                    iconColor: .green,
                    title: "开机自动启动 LiquidClip",
                    subtitle: "登录 macOS 后静默常驻菜单栏，不占用 Dock 空间",
                    isOn: $settings.launchAtLogin
                )
                
                SettingsRowDivider()
                
                SettingsToggleRow(
                    icon: "123.rectangle.fill",
                    iconColor: .orange,
                    title: "列表前 9 项显示数字快捷键角标",
                    subtitle: "呼出后直接按 1~9 无需鼠标即可秒级粘贴对应条目",
                    isOn: $settings.showShortcutsInList
                )
                
                SettingsRowDivider()
                
                SettingsToggleRow(
                    icon: "speaker.wave.2.fill",
                    iconColor: .pink,
                    title: "播放原生系统提示音效",
                    subtitle: "在执行复制、粘贴与删除操作时提供清脆的音频反馈",
                    isOn: $settings.playSounds
                )
            }
        }
    }
}
