import Foundation
import Carbon
import AppKit

final public class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onHotKeyTriggered: (() -> Void)?

    private init() {}

    /// (Re)registers the global hotkey from persisted settings.
    /// Returns false when macOS rejected the registration (e.g. conflict).
    @MainActor
    @discardableResult
    public func registerFromSettings() -> Bool {
        let settings = AppSettings.shared
        return register(keyCode: settings.hotkeyKeyCode, carbonModifiers: settings.hotkeyCarbonModifiers)
    }

    @discardableResult
    public func register(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        unregister()

        let hotKeyID = EventHotKeyID(signature: 0x4C434C50, id: 1) // "LCLP"
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                HotkeyManager.shared.onHotKeyTriggered?()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Failed to register global hotkey (code: \(keyCode), mods: \(carbonModifiers)), status: \(status)")
            return false
        }
        return true
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregister()
    }

    // MARK: - Display Formatting

    /// Carbon modifier mask → "⌃⌥⇧⌘" prefix (canonical order).
    nonisolated public static func modifierDisplay(from carbonModifiers: UInt32) -> String {
        var out = ""
        if carbonModifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out
    }

    /// Human-readable key label for a Carbon virtual key code.
    nonisolated public static func keyDisplay(forVirtualKey keyCode: UInt32, fallback: String? = nil) -> String {
        let special: [UInt32: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
            122: "F1", 120: "F2", 99: "F3", 100: "F4", 101: "F5", 109: "F6",
            103: "F7", 111: "F8", 105: "F9", 106: "F10", 64: "F11", 79: "F12"
        ]
        if let name = special[keyCode] { return name }

        // Resolve printable key via UCKeyTranslate (layout-aware).
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let layout = unsafeBitCast(layoutData, to: CFData.self)
            let layoutPtr = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layoutPtr, UInt16(keyCode), UInt16(kUCKeyActionDown), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, 4, &length, &chars
            )
            if status == noErr && length > 0 {
                let str = String(utf16CodeUnits: chars, count: length).uppercased()
                if !str.isEmpty, let first = str.first, first.isLetter || first.isNumber {
                    return str
                }
            }
        }
        return fallback ?? "Key(\(keyCode))"
    }

    /// NSEvent.ModifierFlags → Carbon modifier mask (for the recorder).
    nonisolated public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}
