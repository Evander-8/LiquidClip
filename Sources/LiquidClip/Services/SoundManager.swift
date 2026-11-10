import Foundation
import AppKit

@MainActor
final public class SoundManager {
    public static let shared = SoundManager()
    
    private let popSound = NSSound(named: "Pop")
    private let tinkSound = NSSound(named: "Tink")
    private let trashSound = NSSound(named: "Purr")
    
    private init() {}
    
    public func playCopy() {
        guard AppSettings.shared.playSounds else { return }
        DispatchQueue.main.async { [weak self] in
            self?.popSound?.play()
        }
    }
    
    public func playPaste() {
        guard AppSettings.shared.playSounds else { return }
        DispatchQueue.main.async { [weak self] in
            self?.tinkSound?.play()
        }
    }
    
    public func playDelete() {
        guard AppSettings.shared.playSounds else { return }
        DispatchQueue.main.async { [weak self] in
            self?.trashSound?.play()
        }
    }
}
