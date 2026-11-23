/**
 * [INPUT]: 依赖 Views/Settings 分栏子页、AboutView、PasteSimulator 与 UpdateChecker
 * [OUTPUT]: 提供 macOS 分栏导航式偏好设置弹窗 SettingsView
 * [POS]: 系统设置中心，作为模态浮层挂载在 MainWindowView 中
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case capture = "粘贴与采集"
    case storage = "存储与数据"
    case privacy = "隐私与安全"
    case about = "关于"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .capture: return "doc.on.clipboard.fill"
        case .storage: return "internaldrive.fill"
        case .privacy: return "hand.raised.fill"
        case .about: return "drop.circle.fill"
        }
    }
    
    public var iconColor: Color {
        switch self {
        case .general: return .gray
        case .capture: return .blue
        case .storage: return .purple
        case .privacy: return .indigo
        case .about: return .teal
        }
    }
    
    public var subtitle: String {
        switch self {
        case .general: return "全局快捷键、开机自启与交互反馈"
        case .capture: return "辅助功能权限、自动粘贴与离线 OCR"
        case .storage: return "本地数据库占用、保留上限与数据清理"
        case .privacy: return "密码管理器过滤、会话无痕与忽略名单"
        case .about: return "版本信息、更新检查与项目主页"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var isAccessibilityGranted: Bool = PasteSimulator.shared.isAccessibilityTrusted
    public var onClose: () -> Void
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }
    
    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Glass Sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("偏好设置")
                        .font(.system(size: 13.5, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarTabRow(tab)
                    }
                }
                .padding(.horizontal, 10)
                
                Spacer()
                
                Divider().opacity(0.3)
                
                Button(action: { selectedTab = .about }) {
                    HStack(spacing: 6) {
                        Text("LiquidClip v\(appVersion)")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        if updateChecker.latestVersion != nil {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 168)
            .background(Color.primary.opacity(0.03))
            
            Divider().opacity(0.4)
            
            // Right Tab Content
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTab.rawValue)
                            .font(.system(size: 15, weight: .bold))
                        Text(selectedTab.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭设置 (Esc)")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.02))
                
                Divider().opacity(0.35)
                
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsTab()
                        case .capture:
                            CaptureSettingsTab(isAccessibilityGranted: isAccessibilityGranted)
                        case .storage:
                            StorageSettingsTab()
                        case .privacy:
                            PrivacySettingsTab()
                        case .about:
                            AboutView(showsCloseButton: false)
                        }
                    }
                    .padding(18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 470)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.28), location: 0),
                            .init(color: Color.white.opacity(0.08), location: 0.5),
                            .init(color: Color.black.opacity(0.18), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.26), radius: 22, y: 8)
        .onAppear {
            isAccessibilityGranted = PasteSimulator.shared.isAccessibilityTrusted
        }
        // Poll only while Accessibility is ungranted; stop immediately once granted or dismissed.
        .task(id: isAccessibilityGranted) {
            guard !isAccessibilityGranted else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let trusted = PasteSimulator.shared.isAccessibilityTrusted
                if trusted != isAccessibilityGranted {
                    isAccessibilityGranted = trusted
                    break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityGranted = PasteSimulator.shared.isAccessibilityTrusted
        }
    }
    
    @ViewBuilder
    private func sidebarTabRow(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        Button(action: {
            withAnimation(.easeInOut(duration: 0.14)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 8) {
                SettingsIconBadge(systemName: tab.iconName, color: tab.iconColor, size: 20)
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if tab == .about && updateChecker.latestVersion != nil {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                if tab == .capture && !isAccessibilityGranted {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
