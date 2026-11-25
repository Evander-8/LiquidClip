/**
 * [INPUT]: 依赖 UserDefaults、LoginService、HotkeyManager 与 StorageManager 的历史裁剪能力
 * [OUTPUT]: 提供全局单例 AppSettings，管理并持久化快捷键（含冲突回滚）、历史上限、默认排除应用、隐私模式与行为偏好
 * [POS]: 全局配置状态中心，被主窗口、设置页、剪贴板监听与存储管理器共同订阅和读取
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import SwiftUI
import Carbon

@MainActor
public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    public static let defaultExcludedApps: [String] = [
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.Passwords",
        "com.apple.keychainaccess"
    ]
    
    @Published public var maxHistoryCount: Int {
        didSet {
            UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount")
            StorageManager.shared.enforceHistoryLimit()
        }
    }
    
    @Published public var autoPasteOnSelect: Bool {
        didSet { UserDefaults.standard.set(autoPasteOnSelect, forKey: "autoPasteOnSelect") }
    }
    
    @Published public var enableSelectionCopy: Bool {
        didSet { UserDefaults.standard.set(enableSelectionCopy, forKey: "enableSelectionCopy") }
    }
    
    @Published public var playSounds: Bool {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    
    @Published public var showShortcutsInList: Bool {
        didSet { UserDefaults.standard.set(showShortcutsInList, forKey: "showShortcutsInList") }
    }
    
    @Published public var windowFollowsCursor: Bool {
        didSet { UserDefaults.standard.set(windowFollowsCursor, forKey: "windowFollowsCursor") }
    }
    
    @Published public var ignorePasswordManagers: Bool {
        didSet { UserDefaults.standard.set(ignorePasswordManagers, forKey: "ignorePasswordManagers") }
    }
    
    @Published public var enableAutoOCR: Bool {
        didSet { UserDefaults.standard.set(enableAutoOCR, forKey: "enableAutoOCR") }
    }
    
    @Published public var excludedApps: [String] {
        didSet { UserDefaults.standard.set(excludedApps, forKey: "excludedApps") }
    }
    
    @Published public var hotkeyDisplay: String {
        didSet { UserDefaults.standard.set(hotkeyDisplay, forKey: "hotkeyDisplay") }
    }

    /// Launch-at-login. Source of truth is the system (SMAppService / login items);
    /// the UserDefaults key only remembers the user's intent while the system call is pending.
    @Published public var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            let applied = LoginService.setEnabled(launchAtLogin)
            if !applied {
                // System rejected it — reflect the real state and stop flip-flopping.
                launchAtLogin = LoginService.isEnabled
            }
        }
    }

    /// Privacy mode: pauses all disk/SQLite writes while retaining existing persisted
    /// history untouched; ephemeral items and images stay in memory and are purged on disable.
    @Published public var privacyMode: Bool {
        didSet {
            guard oldValue != privacyMode else { return }
            UserDefaults.standard.set(privacyMode, forKey: "privacyMode")
            StorageManager.shared.applyPrivacyMode(enabled: privacyMode)
        }
    }

    /// Global hotkey virtual key code (Carbon), persisted.
    @Published public var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") }
    }

    /// Global hotkey Carbon modifier mask (cmdKey/shiftKey/optionKey/controlKey), persisted.
    @Published public var hotkeyCarbonModifiers: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotkeyCarbonModifiers), forKey: "hotkeyCarbonModifiers") }
    }
    
    private init() {
        let defaults = UserDefaults.standard
        self.maxHistoryCount = defaults.object(forKey: "maxHistoryCount") != nil ? defaults.integer(forKey: "maxHistoryCount") : 200
        self.autoPasteOnSelect = defaults.object(forKey: "autoPasteOnSelect") != nil ? defaults.bool(forKey: "autoPasteOnSelect") : true
        self.enableSelectionCopy = defaults.bool(forKey: "enableSelectionCopy")
        self.playSounds = defaults.object(forKey: "playSounds") != nil ? defaults.bool(forKey: "playSounds") : true
        self.showShortcutsInList = defaults.object(forKey: "showShortcutsInList") != nil ? defaults.bool(forKey: "showShortcutsInList") : true
        self.windowFollowsCursor = defaults.object(forKey: "windowFollowsCursor") != nil ? defaults.bool(forKey: "windowFollowsCursor") : true
        self.ignorePasswordManagers = defaults.object(forKey: "ignorePasswordManagers") != nil ? defaults.bool(forKey: "ignorePasswordManagers") : true
        self.enableAutoOCR = defaults.object(forKey: "enableAutoOCR") != nil ? defaults.bool(forKey: "enableAutoOCR") : true
        self.excludedApps = defaults.stringArray(forKey: "excludedApps") ?? Self.defaultExcludedApps
        self.hotkeyDisplay = defaults.string(forKey: "hotkeyDisplay") ?? "⌘ ⇧ V"
        self.launchAtLogin = LoginService.isEnabled
        self.privacyMode = defaults.bool(forKey: "privacyMode")
        let hasSavedHotkey = defaults.object(forKey: "hotkeyKeyCode") != nil
            && defaults.object(forKey: "hotkeyCarbonModifiers") != nil
        if hasSavedHotkey {
            let savedKeyCode = UInt32(max(0, defaults.integer(forKey: "hotkeyKeyCode")))
            let savedMods = UInt32(max(0, defaults.integer(forKey: "hotkeyCarbonModifiers")))
            self.hotkeyKeyCode = savedKeyCode
            self.hotkeyCarbonModifiers = savedMods > 0 ? savedMods : UInt32(cmdKey | shiftKey)
        } else {
            // Defaults: ⌘ + ⇧ + V (V = 9, cmdKey | shiftKey)
            self.hotkeyKeyCode = 9
            self.hotkeyCarbonModifiers = UInt32(cmdKey | shiftKey)
        }
    }

    /// Applies a newly recorded hotkey: registers with Carbon first, persisting on success
    /// or restoring the previous registration on conflict.
    @discardableResult
    public func setHotkey(keyCode: UInt32, carbonModifiers: UInt32, display: String) -> Bool {
        let oldCode = self.hotkeyKeyCode
        let oldMods = self.hotkeyCarbonModifiers
        guard HotkeyManager.shared.register(keyCode: keyCode, carbonModifiers: carbonModifiers) else {
            HotkeyManager.shared.register(keyCode: oldCode, carbonModifiers: oldMods)
            return false
        }
        self.hotkeyKeyCode = keyCode
        self.hotkeyCarbonModifiers = carbonModifiers
        self.hotkeyDisplay = display
        return true
    }
}
