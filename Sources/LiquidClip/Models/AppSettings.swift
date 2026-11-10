import Foundation
import SwiftUI

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
            "org.keepassxc.keepassxc",
            "com.apple.keychainaccess"
        ]
        self.hotkeyDisplay = defaults.string(forKey: "hotkeyDisplay") ?? "⌘ ⇧ V"
    }
}
