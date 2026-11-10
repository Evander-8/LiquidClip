import Foundation
import AppKit
import SwiftUI

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingPanel: FloatingPanel?
    private var menuBarController: MenuBarController?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory app (no dock icon clutter)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup Floating Window
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540))
        let mainView = MainWindowView(
            onClose: { [weak panel] in
                panel?.hideImmediately()
            },
            registerKeyHandler: { [weak panel] handler in
                panel?.onKeyDown = handler
            }
        )
        panel.contentView = NSHostingView(rootView: mainView)
        self.floatingPanel = panel
        
        // Setup Menu Bar Status Item
        self.menuBarController = MenuBarController(floatingPanel: panel)
        
        // Start Clipboard Monitoring
        ClipboardMonitor.shared.startMonitoring()
        
        // Register Global Carbon HotKey (⌘ + ⇧ + V)
        HotkeyManager.shared.onHotKeyTriggered = { [weak panel] in
            panel?.toggleVisibility()
        }
        HotkeyManager.shared.registerDefaultHotKey()
        
        print("LiquidClip launched successfully.")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        HotkeyManager.shared.unregister()
    }
}
