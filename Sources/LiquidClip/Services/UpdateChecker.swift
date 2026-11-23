/**
 * [INPUT]: 依赖 Foundation URLSession、AppKit 与 Bundle 版本元数据
 * [OUTPUT]: 提供 GitHub Releases 版本检测单例 UpdateChecker，支持静默检查与交互式状态反馈
 * [POS]: 应用更新检测服务，被 AppDelegate、MenuBarController、MainWindowView 与 AboutView 订阅
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import AppKit

/// Lightweight GitHub Releases update check — one URLSession call at launch,
/// no third-party framework (Sparkle not needed for a menu-bar utility).
@MainActor
public class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    /// GitHub org/repo — single source of truth for both check & download URLs.
    public static let repoPath = "Evander-8/LiquidClip"

    /// Remote tag (e.g. "v1.0.4") when a newer release exists, otherwise nil.
    @Published public var latestVersion: String?
    @Published public var isChecking: Bool = false
    @Published public var checkFeedback: String? = nil
    public var latestReleaseURL: URL? {
        URL(string: "https://github.com/\(Self.repoPath)/releases/latest")
    }

    /// Posted (on main) whenever a new version is detected, so UI surfaces
    /// (status-item badge, banners) can light up. userInfo: ["version": String]
    public static let updateFoundNotification = Notification.Name("LiquidClipUpdateFound")

    private var checked = false
    private init() {}

    public func checkForUpdateOnce() {
        guard !checked else { return }
        checked = true
        checkForUpdate(interactive: false)
    }

    public func checkForUpdate(interactive: Bool = false) {
        guard !isChecking else { return }
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoPath)/releases/latest") else { return }
        if interactive {
            isChecking = true
            checkFeedback = nil
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let parsedTag: String?
            if error == nil,
               let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = obj["tag_name"] as? String {
                parsedTag = tag
            } else {
                parsedTag = nil
            }
            let local = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isChecking = false
                guard let tag = parsedTag else {
                    if interactive {
                        self.checkFeedback = "检查更新失败，请稍后重试"
                    }
                    return
                }
                let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if Self.isVersion(remote, newerThan: local) {
                    self.latestVersion = tag
                    self.checkFeedback = nil
                    NotificationCenter.default.post(name: Self.updateFoundNotification, object: nil,
                                                    userInfo: ["version": tag])
                    self.presentOneTimeAlert(version: tag, current: local)
                } else {
                    self.latestVersion = nil
                    if interactive {
                        self.checkFeedback = "当前已是最新版本 (v\(local))"
                    }
                }
            }
        }.resume()
    }

    /// Prominent launch alert — shown at most once per remote version (persisted),
    /// so it stays visible without becoming nagging.
    private func presentOneTimeAlert(version: String, current: String) {
        let key = "updateAlertShownFor/\(version)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "🎉 LiquidClip 发现新版本 \(version)"
        alert.informativeText = "当前版本 v\(current)。新版本包含性能优化与功能改进，是否前往下载页？"
        alert.alertStyle = .informational
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后再说")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = latestReleaseURL {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Semantic-ish comparison on dot-separated numeric components ("1.10" > "1.9").
    nonisolated public static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
