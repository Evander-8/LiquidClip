import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = StorageManager.shared
    @State private var isAccessibilityGranted: Bool = PasteSimulator.shared.isAccessibilityTrusted
    @State private var showClearConfirm = false
    public var onClose: () -> Void
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.accentColor)
                    Text("偏好设置")
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.03))
            
            Divider().opacity(0.4)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Accessibility Permission Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("系统权限")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(isAccessibilityGranted ? .green : .orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("辅助功能权限 (自动粘贴)")
                                    .font(.system(size: 13, weight: .medium))
                                Text(isAccessibilityGranted ? "已获得授权，选中记录可自动粘贴至目标窗口。" : "未获得授权。选中记录时将只复制到剪贴板，需手动 ⌘V 粘贴。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if !isAccessibilityGranted {
                                Button("去授权") {
                                    PasteSimulator.shared.openAccessibilitySettings()
                                    // Refresh status after slight delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        isAccessibilityGranted = PasteSimulator.shared.isAccessibilityTrusted
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(10)
                    }
                    
                    // History & Memory Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("历史与存储")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("最大历史记录保留数")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $settings.maxHistoryCount) {
                                Text("50 条").tag(50)
                                Text("100 条").tag(100)
                                Text("200 条 (推荐)").tag(200)
                                Text("500 条").tag(500)
                                Text("1000 条").tag(1000)
                            }
                            .frame(width: 140)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("清空普通历史记录")
                                    .font(.system(size: 13))
                                Text("保留已收藏项与所有自定义分组内的记录")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    showClearConfirm.toggle()
                                }
                            }) {
                                Text(showClearConfirm ? "收起确认" : "清空普通历史")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if showClearConfirm {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 12))
                                    Text("确定清空吗？已收藏与自定义分组内的记录将永久保留。")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                
                                HStack(spacing: 8) {
                                    Spacer()
                                    Button("取消") {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            showClearConfirm = false
                                        }
                                    }
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(6)
                                    .buttonStyle(.plain)
                                    
                                    Button("确认清空") {
                                        storage.clearUnpinned()
                                        SoundManager.shared.playDelete()
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            showClearConfirm = false
                                        }
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(6)
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
                    // Behavior Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("快捷操作与反馈")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Toggle("选中历史项时自动执行粘贴 (⌘V)", isOn: $settings.autoPasteOnSelect)
                            .font(.system(size: 13))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("划词自动复制 (划选文本即记录)", isOn: $settings.enableSelectionCopy)
                                .font(.system(size: 13))
                                .onChange(of: settings.enableSelectionCopy) {
                                    ClipboardMonitor.shared.setupMouseSelectionMonitor()
                                }
                            Text("关闭时，忽略终端（如 Ghostty/iTerm）等应用的划选自动抓取，仅在按下 ⌘C 时才记录。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.leading, 18)
                        }
                        
                        Toggle("播放原生音效提示 (复制/粘贴/删除)", isOn: $settings.playSounds)
                            .font(.system(size: 13))
                        
                        Toggle("在列表前 9 项显示数字快捷键角标 (1~9 直达)", isOn: $settings.showShortcutsInList)
                            .font(.system(size: 13))
                        
                        Toggle("呼出窗口时跟随鼠标所在屏幕", isOn: $settings.windowFollowsCursor)
                            .font(.system(size: 13))
                    }
                    
                    // Privacy & Security
                    VStack(alignment: .leading, spacing: 12) {
                        Text("隐私与安全")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Toggle("忽略密码管理器复制的内容 (1Password / Bitwarden / 钥匙串等)", isOn: $settings.ignorePasswordManagers)
                            .font(.system(size: 13))
                    }
                    
                    // About Section with Version & Build
                    VStack(spacing: 8) {
                        Divider().opacity(0.3)
                            .padding(.top, 4)
                        
                        HStack(spacing: 10) {
                            if let icon = NSApp.applicationIconImage {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 34, height: 34)
                                    .shadow(color: Color.black.opacity(0.2), radius: 3, y: 1)
                            } else {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.cyan)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("LiquidClip 流光剪贴板")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("v\(appVersion)")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }
                                
                                Text("原生液态玻璃架构 · Swift 6 + SwiftUI · 内存占用 < 18MB")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Build \(appBuild)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                
                                Button(action: {
                                    if let url = URL(string: "https://github.com/Evander-8/LiquidClip") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                                            .font(.system(size: 8))
                                        Text("GitHub")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                                .help("访问 GitHub 开源仓库")
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Text("开源项目主页:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Link("https://github.com/Evander-8/LiquidClip", destination: URL(string: "https://github.com/Evander-8/LiquidClip")!)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        .padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 480)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            isAccessibilityGranted = PasteSimulator.shared.isAccessibilityTrusted
        }
    }
}
