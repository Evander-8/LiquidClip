/**
 * [INPUT]: 依赖 UpdateChecker、AppSettings、StorageManager、ClipboardMonitor 与 SoundManager
 * [OUTPUT]: 提供可复用的液态玻璃关于界面 AboutView，支持版本徽章、交互式检查更新、架构微卡片与一键复制诊断信息
 * [POS]: 兼具独立窗口内容视图（MenuBarController -> AboutWindowController）与设置中心「关于」子页双重角色
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct AboutView: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = StorageManager.shared
    
    public var showsCloseButton: Bool
    public var onClose: (() -> Void)?
    
    @State private var copiedDiagnostics = false
    
    public init(showsCloseButton: Bool = false, onClose: (() -> Void)? = nil) {
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }
    
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "8"
    }
    
    private var repoURL: URL {
        URL(string: "https://github.com/\(UpdateChecker.repoPath)")!
    }
    
    private var issuesURL: URL {
        URL(string: "https://github.com/\(UpdateChecker.repoPath)/issues")!
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            if showsCloseButton {
                HStack {
                    Spacer()
                    Button(action: { onClose?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭 (Esc)")
                }
                .padding(.bottom, -10)
            }
            
            // Hero Header
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.accentColor.opacity(0.32), Color.cyan.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 6,
                                endRadius: 52
                            )
                        )
                        .frame(width: 96, height: 96)
                    
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
                    } else {
                        Image(systemName: "drop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)
                    }
                }
                
                VStack(spacing: 4) {
                    Text("LiquidClip 流光剪贴板")
                        .font(.system(size: 18, weight: .bold))
                    
                    HStack(spacing: 6) {
                        Text("v\(appVersion)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(Capsule())
                        
                        Text("Build \(appBuild)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("专为 macOS 打造的纯原生液态玻璃剪贴板历史管理器")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            
            // Interactive Update Check Bar
            updateCard
            
            // Architecture & Specs Grid (3 columns)
            HStack(spacing: 8) {
                specCard(icon: "swift", color: .orange, title: "纯原生架构", value: "Swift + AppKit")
                specCard(icon: "cylinder.split.1x2.fill", color: .teal, title: "存储引擎", value: "SQLite3 FTS5")
                specCard(icon: "command", color: .blue, title: "全局快捷键", value: settings.hotkeyDisplay)
            }
            
            // Quick Action Links
            HStack(spacing: 8) {
                actionPill(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub 仓库") {
                    NSWorkspace.shared.open(repoURL)
                }
                actionPill(icon: "shippingbox.fill", title: "版本发布") {
                    if let url = checker.latestReleaseURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                actionPill(icon: "exclamationmark.bubble.fill", title: "问题反馈") {
                    NSWorkspace.shared.open(issuesURL)
                }
                actionPill(
                    icon: copiedDiagnostics ? "checkmark.circle.fill" : "doc.on.clipboard",
                    title: copiedDiagnostics ? "已复制" : "诊断信息",
                    tint: copiedDiagnostics ? .green : .primary
                ) {
                    copyDiagnostics()
                }
            }
            
            // Footer
            VStack(spacing: 3) {
                Divider().opacity(0.3)
                Text("MIT License · 100% 本地离线存储 · Copyright © 2026 Evander-8")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.top, 6)
            }
        }
    }
    
    @ViewBuilder
    private var updateCard: some View {
        HStack(spacing: 10) {
            if let version = checker.latestVersion {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("发现新版本 \(version)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                    Text("点击前往 GitHub Releases 下载最新版本")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("前往下载") {
                    if let url = checker.latestReleaseURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green)
                .cornerRadius(6)
                .buttonStyle(.plain)
            } else {
                Image(systemName: checker.isChecking ? "arrow.triangle.2.circlepath" : "checkmark.seal.fill")
                    .font(.system(size: 15))
                    .foregroundColor(checker.isChecking ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(checker.isChecking ? "正在连接 GitHub 检查更新…" : (checker.checkFeedback ?? "检查 GitHub Releases 更新"))
                        .font(.system(size: 11.5, weight: .medium))
                    Text("当前版本 v\(appVersion) (Build \(appBuild))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(checker.isChecking ? "检查中…" : "检查更新") {
                    checker.checkForUpdate(interactive: true)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(checker.isChecking)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(checker.latestVersion != nil ? Color.green.opacity(0.09) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(checker.latestVersion != nil ? Color.green.opacity(0.28) : Color.white.opacity(0.09), lineWidth: 0.6)
        )
    }
    
    private func specCard(icon: String, color: Color, title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
    
    private func actionPill(
        icon: String,
        title: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6.5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
    
    private func copyDiagnostics() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let info = """
        LiquidClip v\(appVersion) (Build \(appBuild))
        macOS: \(osVersion)
        Items: \(storage.items.count), Groups: \(storage.groups.count)
        AutoOCR: \(settings.enableAutoOCR), PrivacyMode: \(settings.privacyMode)
        Accessibility: \(PasteSimulator.shared.isAccessibilityTrusted)
        """
        ClipboardMonitor.shared.isSelfCopying = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(info, forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
        SoundManager.shared.playCopy()
        
        withAnimation { copiedDiagnostics = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { copiedDiagnostics = false }
        }
    }
}
