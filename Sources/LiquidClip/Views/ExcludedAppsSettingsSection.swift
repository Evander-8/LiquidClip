/**
 * [INPUT]: 依赖 AppSettings、AppIconView 与 NSWorkspace 运行应用列表
 * [OUTPUT]: 提供忽略应用可视化管理组件 ExcludedAppsSettingsSection
 * [POS]: SettingsView 隐私与安全区的子组件，支持从运行中应用一键添加或手动输入 Bundle ID
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct ExcludedAppsSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newBundleId: String = ""
    
    public init() {}
    
    private var runningSelectableApps: [(name: String, bundleId: String)] {
        let existing = Set(settings.excludedApps.map { $0.lowercased() })
        let selfId = Bundle.main.bundleIdentifier?.lowercased() ?? ""
        var seen = Set<String>()
        var result: [(String, String)] = []
        
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, !bid.isEmpty else { continue }
            let lower = bid.lowercased()
            if lower == selfId || existing.contains(lower) || seen.contains(lower) {
                continue
            }
            seen.insert(lower)
            result.append((app.localizedName ?? bid, bid))
        }
        return result.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("忽略指定应用 (不记录来自这些应用的复制)")
                        .font(.system(size: 13))
                    Text("默认已包含常见密码管理器，可随时增删其他敏感应用。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Menu {
                    let apps = runningSelectableApps
                    if apps.isEmpty {
                        Text("暂无其他可添加的运行中应用")
                    } else {
                        ForEach(apps, id: \.bundleId) { app in
                            Button(action: {
                                addExcludedApp(app.bundleId)
                            }) {
                                Text("\(app.name) (\(app.bundleId))")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.app")
                            .font(.system(size: 10))
                        Text("从运行中添加")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Manual Bundle ID input
            HStack(spacing: 6) {
                TextField("手动输入 Bundle ID (例如 com.apple.Notes)", text: $newBundleId)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                
                Button("添加") {
                    addExcludedApp(newBundleId)
                    newBundleId = ""
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.15))
                .foregroundColor(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                .cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            if !settings.excludedApps.isEmpty {
                VStack(spacing: 4) {
                    ForEach(settings.excludedApps, id: \.self) { bundleId in
                        HStack(spacing: 8) {
                            AppIconView(bundleId: bundleId, size: 16)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appDisplayName(for: bundleId))
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text(bundleId)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                settings.excludedApps.removeAll { $0.caseInsensitiveCompare(bundleId) == .orderedSame }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .help("从忽略列表移除")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.6)
        )
    }
    
    private func addExcludedApp(_ rawId: String) {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !settings.excludedApps.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            settings.excludedApps.append(trimmed)
        }
    }
    
    private func appDisplayName(for bundleId: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return appURL.deletingPathExtension().lastPathComponent
        }
        return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }
}
