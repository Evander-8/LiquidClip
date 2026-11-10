import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    public static let floatingPanelDidHide = Notification.Name("FloatingPanelDidHideNotification")
    public static let floatingPanelWillShow = Notification.Name("FloatingPanelWillShowNotification")
}

@MainActor
public class FloatingPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovableByWindowBackground = true
        self.animationBehavior = .none
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    // Window-level key event interceptor (captures ESC, arrows, enter regardless of which control is focused)
    public var onKeyDown: ((NSEvent) -> Bool)?
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let onKeyDown = onKeyDown, onKeyDown(event) {
                return
            }
            // Absolute fallback: ESC (53) always dismisses the floating panel
            if event.keyCode == 53 {
                self.hideImmediately()
                return
            }
        }
        super.sendEvent(event)
    }
    
    public override func cancelOperation(_ sender: Any?) {
        if let onKeyDown = onKeyDown {
            let dummy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: self.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)
            if let dummy = dummy, onKeyDown(dummy) {
                return
            }
        }
        self.hideImmediately()
    }
    
    // Automatically close when losing focus to another application
    public override func resignKey() {
        super.resignKey()
        guard isVisible else { return }
        
        // If window has an attached sheet or child window, keep open
        if self.attachedSheet != nil || !(self.childWindows?.isEmpty ?? true) {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isVisible else { return }
                
                // If attached sheet or child window exists, do not hide
                if self.attachedSheet != nil || !(self.childWindows?.isEmpty ?? true) {
                    return
                }
                
                // If an internal sheet, menu or app window is key, do not hide
                if let keyWin = NSApp.keyWindow {
                    if keyWin == self || keyWin.parent == self || keyWin.sheetParent == self {
                        return
                    }
                }
                
                // Only hide if the user actually switched to another app
                if !self.isKeyWindow {
                    self.hideImmediately()
                }
            }
        }
    }
    
    public func toggleVisibility() {
        if isVisible {
            hideImmediately()
        } else {
            showSmoothly()
        }
    }
    
    public func showSmoothly() {
        NotificationCenter.default.post(name: .floatingPanelWillShow, object: self)
        
        // Record the frontmost app so we can paste back to it
        PasteSimulator.shared.recordFrontmostApp()
        PasteSimulator.shared.refreshAccessibilityStatus()
        
        positionWindow()
        self.alphaValue = 0.0
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    // Instant hide for zero-latency pasting and dismissal (vanishes in 0ms)
    public func hideImmediately() {
        self.orderOut(nil)
        self.alphaValue = 0.0
        NotificationCenter.default.post(name: .floatingPanelDidHide, object: self)
    }
    
    public func hideSmoothly() {
        hideImmediately()
    }
    
    // Position window in the center of the active screen (or mouse screen)
    private func positionWindow() {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first
        
        guard let screen = targetScreen else { return }
        
        let screenRect = screen.visibleFrame
        let windowWidth = self.frame.width
        let windowHeight = self.frame.height
        
        let x = screenRect.origin.x + (screenRect.width - windowWidth) / 2
        // Slightly above vertical center for optimal viewing angle (Spotlight style)
        let y = screenRect.origin.y + (screenRect.height - windowHeight) / 2 + 30
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
