import Foundation
import SwiftUI
import Carbon

@MainActor
public class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    @Published public var maxHistoryCount: Int {
        didSet { UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount") }
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

    /// Privacy mode: history lives in memory only for the session — nothing is
    /// written to disk (existing files are wiped on enable, save resumes on disable).
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
        self.excludedApps = defaults.stringArray(forKey: "excludedApps") ?? [
            "com.agilebits.onepassword",
            "com.agilebits.onepassword7",
            "com.1password.1password",
            "com.bitwarden.desktop",
            "org.keepassxc.keepassxc"
        ]
        self.hotkeyDisplay = defaults.string(forKey: "hotkeyDisplay") ?? "⌘ ⇧ V"
        self.launchAtLogin = LoginService.isEnabled
        self.privacyMode = defaults.bool(forKey: "privacyMode")
        let savedKeyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
        let savedMods = UInt32(defaults.integer(forKey: "hotkeyCarbonModifiers"))
        // Defaults: ⌘ + ⇧ + V (V = 9, cmdKey | shiftKey)
        self.hotkeyKeyCode = savedKeyCode > 0 ? savedKeyCode : 9
        self.hotkeyCarbonModifiers = savedMods > 0 ? savedMods : UInt32(cmdKey | shiftKey)
    }

    /// Applies a newly recorded hotkey: persists it and re-registers with Carbon.
    public func setHotkey(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.hotkeyKeyCode = keyCode
        self.hotkeyCarbonModifiers = carbonModifiers
        self.hotkeyDisplay = display
        HotkeyManager.shared.register(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }
}
