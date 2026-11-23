/**
 * [INPUT]: 依赖 SwiftUI、AppKit、Carbon、AppSettings 与 HotkeyManager
 * [OUTPUT]: 提供设置界面基础组件：SettingsIconBadge、SettingsGroupCard、SettingsToggleRow、SettingsRowDivider 与 HotkeyRecorderPill
 * [POS]: Views/Settings 共享原语库，统一各设置子页的 macOS 液态玻璃卡片与控件视觉规范
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit
import Carbon

public struct SettingsIconBadge: View {
    public let systemName: String
    public let color: Color
    public var size: CGFloat
    
    public init(systemName: String, color: Color, size: CGFloat = 24) {
        self.systemName = systemName
        self.color = color
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.92), color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
            Image(systemName: systemName)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

public struct SettingsGroupCard<Content: View>: View {
    public let title: String?
    public let footer: String?
    @ViewBuilder public let content: () -> Content
    
    public init(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.6)
            )
            
            if let footer = footer {
                Text(footer)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.85))
                    .padding(.horizontal, 4)
            }
        }
    }
}

public struct SettingsToggleRow: View {
    public let icon: String
    public let iconColor: Color
    public let title: String
    public var subtitle: String?
    @Binding public var isOn: Bool
    
    public init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            SettingsIconBadge(systemName: icon, color: iconColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 8)
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

public struct SettingsRowDivider: View {
    public init() {}
    
    public var body: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, 46)
    }
}

// MARK: - Hotkey Recorder Pill

public struct HotkeyRecorderPill: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    
    public init() {}
    
    private var isDefaultHotkey: Bool {
        settings.hotkeyKeyCode == 9 && settings.hotkeyCarbonModifiers == UInt32(cmdKey | shiftKey)
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            if !isDefaultHotkey && !isRecording {
                Button("恢复默认") {
                    settings.setHotkey(keyCode: 9, carbonModifiers: UInt32(cmdKey | shiftKey), display: "⌘ ⇧ V")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .help("恢复默认快捷键 ⌘ ⇧ V")
            }
            
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 5) {
                    if isRecording {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                        Text("按下新快捷键… (Esc 取消)")
                            .font(.system(size: 11, weight: .semibold))
                    } else {
                        Text(settings.hotkeyDisplay)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        Text("点击修改")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(isRecording ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isRecording ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
        }
        .onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierOnlyKeyCodes.contains(event.keyCode) {
                return nil
            }
            let carbonMods = HotkeyManager.carbonModifiers(from: event.modifierFlags)
            guard carbonMods != 0 else {
                return nil
            }
            let keyLabel = HotkeyManager.keyDisplay(forVirtualKey: UInt32(event.keyCode))
            let display = HotkeyManager.modifierDisplay(from: carbonMods) + " " + keyLabel
            settings.setHotkey(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods, display: display)
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
