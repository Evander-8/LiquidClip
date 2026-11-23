/**
 * [INPUT]: 依赖 AppSettings、SettingsComponents 与 ExcludedAppsSettingsSection
 * [OUTPUT]: 提供「隐私与安全」设置分栏视图 PrivacySettingsTab（密码管理器过滤、无痕隐私模式与忽略应用管理）
 * [POS]: SettingsView 的隐私与安全分类子页
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI

public struct PrivacySettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.privacyMode {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("隐私模式已开启：新增文本与图片仅驻留内存、绝不写入磁盘或数据库，关闭或退出后自动清除。")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.purple.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.purple.opacity(0.3), lineWidth: 0.6))
            }
            
            SettingsGroupCard(title: "隐私保护策略") {
                SettingsToggleRow(
                    icon: "key.fill",
                    iconColor: .yellow,
                    title: "自动忽略密码管理器内容",
                    subtitle: "识别 1Password、Bitwarden、KeePassXC 与苹果钥匙串等 Concealed 标记",
                    isOn: $settings.ignorePasswordManagers
                )
                
                SettingsRowDivider()
                
                SettingsToggleRow(
                    icon: "eye.slash.fill",
                    iconColor: .purple,
                    title: "会话级隐私模式 (不落盘)",
                    subtitle: "开启后新复制的内容仅保留在内存中；已有分组与历史不受影响",
                    isOn: $settings.privacyMode
                )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("应用黑名单")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                ExcludedAppsSettingsSection()
            }
        }
    }
}
