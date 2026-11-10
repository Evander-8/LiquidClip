import Foundation
import AppKit
import CoreGraphics

@MainActor
public class PasteSimulator {
    public static let shared = PasteSimulator()
    
    public var previousApp: NSRunningApplication?
    
    private init() {}
    
    private var _cachedAccessibility: Bool?
    
    // Check whether the app has Accessibility permissions (cached for 0ms check)
    public var isAccessibilityTrusted: Bool {
        if let cached = _cachedAccessibility {
            return cached
        }
        let trusted = AXIsProcessTrusted()
        _cachedAccessibility = trusted
        return trusted
    }
    
    public func refreshAccessibilityStatus() {
        _cachedAccessibility = AXIsProcessTrusted()
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
    
    // Copy item to system pasteboard
    public func copyToPasteboard(item: ClipItem) {
        ClipboardMonitor.shared.isSelfCopying = true
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.type {
        case .text, .color, .url:
            if let text = item.plainText {
                pb.setString(text, forType: .string)
            }
            if let html = item.htmlText {
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
    
    // Perform paste action
    @discardableResult
    public func paste(item: ClipItem, closeAction: () -> Void) -> Bool {
        // 1. Instantly hide window FIRST (0ms latency, vanishes on the exact click frame!)
        closeAction()
        
        // 2. Perform pasteboard copy, target activation, and simulated paste asynchronously
        // on the next runloop cycle. This ensures the window unmap is flushed to screen
        // with ZERO frame drops or Mach IPC delays!
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.copyToPasteboard(item: item)
            
            let shouldAutoPaste = AppSettings.shared.autoPasteOnSelect
            guard shouldAutoPaste else {
                SoundManager.shared.playCopy()
                return
            }
            
            let targetApp = self.previousApp
            
            // Reactivate target app
            if let target = targetApp, !target.isTerminated {
                if #available(macOS 14.0, *) {
                    target.activate()
                } else {
                    target.activate(options: .activateIgnoringOtherApps)
                }
            }
            
            SoundManager.shared.playPaste()
            
            // Simulate Command+V with minimal delay (35ms) after target app gains focus
            if self.isAccessibilityTrusted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                    self.simulateCommandV()
                }
            }
        }
        
        return true
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
