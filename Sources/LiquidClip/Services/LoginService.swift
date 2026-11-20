import Foundation
import ServiceManagement
import CoreServices

/// Launch-at-login management.
/// Primary: SMAppService (macOS 13+). Fallback: legacy LSSharedFileList session
/// login items, which also works for ad-hoc signed apps that SMAppService rejects.
@MainActor
public enum LoginService {

    public static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled {
            return true
        }
        return legacyContainsApp()
    }

    /// Returns true when the requested state took effect.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                do {
                    try SMAppService.mainApp.register()
                    return true
                } catch {
                    // Ad-hoc / unsigned builds are often rejected here — fall back.
                }
            }
            if !legacyContainsApp() {
                legacyInsertApp()
            }
            return legacyContainsApp() || SMAppService.mainApp.status == .enabled
        } else {
            if SMAppService.mainApp.status == .enabled {
                do {
                    try SMAppService.mainApp.unregister()
                } catch {
                    // ignore; legacy removal below still runs
                }
            }
            legacyRemoveApp()
            return !legacyContainsApp() && SMAppService.mainApp.status != .enabled
        }
    }

    // MARK: - Legacy LSSharedFileList fallback

    private static func legacyList() -> LSSharedFileList? {
        let type = kLSSharedFileListSessionLoginItems.takeRetainedValue()
        guard let raw = LSSharedFileListCreate(kCFAllocatorDefault, type, nil) else { return nil }
        return raw.takeRetainedValue()
    }

    private static func legacyContainsApp() -> Bool {
        guard let list = legacyList(),
              let snapshot = LSSharedFileListCopySnapshot(list, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return false
        }
        let appURL = Bundle.main.bundleURL
        for item in snapshot {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
               itemURL.standardizedFileURL == appURL.standardizedFileURL {
                return true
            }
        }
        return false
    }

    private static func legacyInsertApp() {
        guard let list = legacyList() else { return }
        let seed = kLSSharedFileListItemLast.takeRetainedValue()
        LSSharedFileListInsertItemURL(list, seed, nil, nil, Bundle.main.bundleURL as CFURL, nil, nil)
    }

    private static func legacyRemoveApp() {
        guard let list = legacyList(),
              let snapshot = LSSharedFileListCopySnapshot(list, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return
        }
        let appURL = Bundle.main.bundleURL
        for item in snapshot {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?,
               itemURL.standardizedFileURL == appURL.standardizedFileURL {
                LSSharedFileListItemRemove(list, item)
            }
        }
    }
}
