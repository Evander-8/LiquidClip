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
    public var latestReleaseURL: URL? {
        URL(string: "https://github.com/\(Self.repoPath)/releases/latest")
    }

    private var checked = false
    private init() {}

    public func checkForUpdateOnce() {
        guard !checked else { return }
        checked = true
        checkForUpdate()
    }

    public func checkForUpdate() {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoPath)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let local = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            Task { @MainActor [weak self] in
                if Self.isVersion(remote, newerThan: local) {
                    self?.latestVersion = tag
                }
            }
        }.resume()
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
