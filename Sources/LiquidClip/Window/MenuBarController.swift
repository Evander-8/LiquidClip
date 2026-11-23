import Foundation
import AppKit

@MainActor
public class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var floatingPanel: FloatingPanel?
    
    public init(floatingPanel: FloatingPanel) {
        self.floatingPanel = floatingPanel
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let img = NSImage(systemSymbolName: "drop.circle", accessibilityDescription: "LiquidClip") {
                img.isTemplate = true
                button.image = img
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Light up a green badge dot on the status icon when an update is found.
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateFound(_:)),
            name: UpdateChecker.updateFoundNotification, object: nil
        )
    }

    @objc private func updateFound(_ note: Notification) {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let dot = CALayer()
        dot.name = "updateBadgeDot"
        dot.frame = CGRect(x: layer.bounds.width - 5, y: 1, width: 7, height: 7)
        dot.backgroundColor = NSColor.systemGreen.cgColor
        dot.cornerRadius = 3.5
        dot.borderColor = NSColor.windowBackgroundColor.cgColor
        dot.borderWidth = 1
        // Remove any stale dot before adding (layer width changes with the icon)
        layer.sublayers?.filter { $0.name == "updateBadgeDot" }.forEach { $0.removeFromSuperlayer() }
        layer.addSublayer(dot)
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            floatingPanel?.toggleVisibility()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()

        // Update available: surface it at the very top of the menu.
        if let version = UpdateChecker.shared.latestVersion {
            let updateItem = NSMenuItem(
                title: "🎉 发现新版本 \(version) — 点击更新",
                action: #selector(openLatestRelease), keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        let hotkey = AppSettings.shared.hotkeyDisplay
        let showItem = NSMenuItem(title: "显示剪贴板 (\(hotkey))", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let clearItem = NSMenuItem(title: "清空未收藏记录", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "关于 LiquidClip", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "退出 LiquidClip", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Clear so normal left click works next time
    }
    
    @objc private func togglePanel() {
        floatingPanel?.toggleVisibility()
    }

    @objc private func openSettings() {
        if floatingPanel?.isVisible != true {
            floatingPanel?.showSmoothly()
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openLiquidClipSettings, object: nil)
        }
    }

    @objc private func openLatestRelease() {
        if let url = UpdateChecker.shared.latestReleaseURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func clearHistory() {
        StorageManager.shared.clearUnpinned()
        SoundManager.shared.playDelete()
    }
    
    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
