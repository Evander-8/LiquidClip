/**
 * [INPUT]: 依赖 AppKit、CoreGraphics、ClipItem、AppSettings、ClipboardMonitor 与 SoundManager
 * [OUTPUT]: 提供全局单例 PasteSimulator，负责写入系统剪贴板、模拟 ⌘V 自动粘贴及辅助功能权限检测/修复
 * [POS]: 剪贴板输出执行器，被 FloatingPanel、MainWindowView 与 SettingsView 调用
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit
import CoreGraphics

@MainActor
public class PasteSimulator {
    public static let shared = PasteSimulator()
    
    public var previousApp: NSRunningApplication?
    
    private init() {}
    
    // Check whether the app has Accessibility permissions.
    // AXIsProcessTrusted() is a cheap local IPC call — always query live so the UI
    // reflects a grant made in System Settings immediately (no stale cache).
    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    // Kept for API compatibility; the status is now queried live.
    public func refreshAccessibilityStatus() {}

    // Repair a stale TCC grant: ad-hoc signed apps get their Accessibility entry
    // invalidated after every rebuild (CDHash changes) while the toggle in System
    // Settings still looks ON. Resetting the entry lets the user re-grant cleanly.
    public func repairAccessibilityTrust() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jack.LiquidClip"
        task.arguments = ["reset", "Accessibility", bundleID]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // tccutil reset failed; fall through and just re-prompt.
        }
        // Immediately raise the macOS prompt so the user can re-grant in one step.
        promptForAccessibility()
    }
    
    // Prompt macOS to show the accessibility permission dialog
    public func promptForAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // Open macOS Accessibility settings directly
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Record the currently active app before LiquidClip opens
    public func recordFrontmostApp() {
        let current = NSWorkspace.shared.frontmostApplication
        if let current = current, current.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousApp = current
        }
    }
    
    // Copy item to system pasteboard (set plainTextOnly = true to strip HTML formatting)
    public func copyToPasteboard(item: ClipItem, plainTextOnly: Bool = false) {
        ClipboardMonitor.shared.isSelfCopying = true
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.type {
        case .text, .color, .url:
            if let text = item.plainText {
                pb.setString(text, forType: .string)
            }
            if !plainTextOnly, let html = item.htmlText {
                pb.setString(html, forType: .html)
            }
            
        case .image:
            var fileUrls: [NSPasteboardWriting] = []
            if let paths = item.filePaths {
                for p in paths {
                    fileUrls.append(URL(fileURLWithPath: p) as NSPasteboardWriting)
                }
            }
            if !fileUrls.isEmpty {
                pb.writeObjects(fileUrls)
            }
            if let img = item.loadPrimaryImage(),
               let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            
        case .file:
            if let paths = item.filePaths {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSPasteboardWriting }
                pb.writeObjects(urls)
            }
            if item.isImageFile, let img = item.loadPrimaryImage(), let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
        
        // Synchronize changeCount so monitor doesn't wake up
        ClipboardMonitor.shared.syncChangeCount()
    }
    
    // Perform paste action. Returns false when auto-paste is enabled but Accessibility is missing.
    @discardableResult
    public func paste(item: ClipItem, plainTextOnly: Bool = false, closeAction: () -> Void) -> Bool {
        let shouldAutoPaste = AppSettings.shared.autoPasteOnSelect
        let hasAccessibility = self.isAccessibilityTrusted
        let needsAccessibility = shouldAutoPaste && !hasAccessibility
        
        // 1. Instantly hide window FIRST (0ms latency, vanishes on the exact click frame!)
        closeAction()
        
        // 2. Perform pasteboard copy, target activation, and simulated paste asynchronously
        // on the next runloop cycle. This ensures the window unmap is flushed to screen
        // with ZERO frame drops or Mach IPC delays!
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.copyToPasteboard(item: item, plainTextOnly: plainTextOnly)
            
            guard shouldAutoPaste else {
                SoundManager.shared.playCopy()
                return
            }
            
            let targetApp = self.previousApp
            
            // Reactivate target app (even without Accessibility so the user can press ⌘V immediately)
            if let target = targetApp, !target.isTerminated {
                if #available(macOS 14.0, *) {
                    target.activate()
                } else {
                    target.activate(options: .activateIgnoringOtherApps)
                }
            }
            
            // Simulate Command+V with minimal delay (35ms) after target app gains focus
            if hasAccessibility {
                SoundManager.shared.playPaste()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                    self.simulateCommandV()
                }
            } else {
                SoundManager.shared.playCopy()
            }
        }
        
        return !needsAccessibility
    }
    
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
