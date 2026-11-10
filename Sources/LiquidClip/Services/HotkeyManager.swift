import Foundation
import Carbon
import AppKit

final public class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onHotKeyTriggered: (() -> Void)?
    
    private init() {}
    
    public func registerDefaultHotKey() {
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
        
        // ⌘ + ⇧ + V (cmdKey | shiftKey, virtual key 9 = 'V')
        let modifiers = UInt32(cmdKey | shiftKey)
        let vKeyCode: UInt32 = 9
        
        let status = RegisterEventHotKey(vKeyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Failed to register default hotkey (⌘+⇧+V), status: \(status)")
        } else {
            print("Global hotkey ⌘+⇧+V successfully registered")
        }
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
}
