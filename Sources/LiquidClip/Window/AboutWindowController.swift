/**
 * [INPUT]: 依赖 AppKit NSPanel、SwiftUI、VisualEffectBlur 与 AboutView
 * [OUTPUT]: 提供独立液态玻璃关于窗口控制器 AboutWindowController
 * [POS]: 菜单栏「关于 LiquidClip」的专用单实例浮窗容器
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit
import SwiftUI

@MainActor
public final class AboutWindowController {
    public static let shared = AboutWindowController()
    private var panel: AboutPanel?
    
    private init() {}
    
    public func show() {
        if let existing = panel {
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let panel = AboutPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 470))
        panel.onEscape = { [weak self] in
            self?.close()
        }
        
        let content = AboutView(showsCloseButton: true) { [weak self] in
            self?.close()
        }
        .padding(22)
        .frame(width: 430, height: 470)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.28), location: 0),
                            .init(color: Color.white.opacity(0.08), location: 0.5),
                            .init(color: Color.black.opacity(0.2), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }
    
    public func close() {
        panel?.orderOut(nil)
    }
}

private final class AboutPanel: NSPanel {
    var onEscape: (() -> Void)?
    
    init(contentRect: NSRect) {
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
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
    
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
