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
        
        let showItem = NSMenuItem(title: "显示剪贴板 (⌘⇧V)", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
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
    
    @objc private func clearHistory() {
        StorageManager.shared.clearUnpinned()
        SoundManager.shared.playDelete()
    }
    
    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        
        let alert = NSAlert()
        alert.messageText = "LiquidClip 流光剪贴板 v\(version)"
        alert.informativeText = "版本号: v\(version) (Build \(build))\n\n一款原生液态玻璃质感的轻量 macOS 剪贴板历史管理器。\n\n技术栈: 100% 纯原生 Swift 6 + SwiftUI + AppKit\n内存占用: ~15MB 极度轻量\n全局快捷键: ⌘ + ⇧ + V\n\n开源地址: https://github.com/Evander-8/LiquidClip\n\nCopyright © 2026 LiquidClip. All rights reserved."
        alert.alertStyle = .informational
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "访问 GitHub 仓库")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/Evander-8/LiquidClip") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
