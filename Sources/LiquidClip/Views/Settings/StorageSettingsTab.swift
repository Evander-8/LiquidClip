/**
 * [INPUT]: 依赖 AppSettings、StorageManager、SoundManager 与 SettingsComponents
 * [OUTPUT]: 提供「存储与数据」设置分栏视图 StorageSettingsTab（SQLite 存储概览、容量上限、数据目录打开与安全清理）
 * [POS]: SettingsView 的存储与数据分类子页
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import SwiftUI
import AppKit

public struct StorageSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = StorageManager.shared
    @State private var showClearConfirm = false
    @State private var diskBytes: Int64 = 0
    @State private var imageFileCount: Int = 0
    @State private var isCalculatingFootprint = true
    
    public init() {}
    
    private var protectedCount: Int {
        storage.items.filter { $0.isPinned || $0.groupId != nil }.count
    }
    
    private var formattedSize: String {
        if isCalculatingFootprint { return "计算中…" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: diskBytes)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Live Storage Metrics
            HStack(spacing: 8) {
                storageMetricCard(icon: "tray.full.fill", color: .blue, title: "历史总记录", value: "\(storage.items.count) 条")
                storageMetricCard(icon: "shield.checkered", color: .orange, title: "受保护条目", value: "\(protectedCount) 条")
                storageMetricCard(icon: "internaldrive.fill", color: .purple, title: "本地占用 (\(imageFileCount) 图)", value: formattedSize)
            }
            
            SettingsGroupCard(title: "历史保留与目录") {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "clock.arrow.circlepath", color: .blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("普通历史最大保留条数")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("已收藏与自定义分组内的条目永久保留，不受此上限影响")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Picker("", selection: $settings.maxHistoryCount) {
                        Text("50 条").tag(50)
                        Text("100 条").tag(100)
                        Text("200 条 (推荐)").tag(200)
                        Text("500 条").tag(500)
                        Text("1000 条").tag(1000)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                
                SettingsRowDivider()
                
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "folder.fill", color: .teal)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本地数据库与图片目录")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("SQLite3 (FTS5) + 图片缓存均存储在本地，无云端上传")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Button("在访达中打开") {
                        NSWorkspace.shared.open(storage.dataDirectoryURL)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            
            SettingsGroupCard(title: "数据清理") {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        SettingsIconBadge(systemName: "trash.fill", color: .red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("清空普通历史记录")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("仅移除未收藏且未归入自定义分组的临时碎片记录")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                showClearConfirm.toggle()
                            }
                        }) {
                            Text(showClearConfirm ? "收起确认" : "清空历史")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    
                    if showClearConfirm {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 11))
                                Text("确定清空吗？已收藏与自定义分组内的 \(protectedCount) 条记录将永久保留。")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.red)
                            }
                            
                            HStack(spacing: 8) {
                                Spacer()
                                Button("取消") {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        showClearConfirm = false
                                    }
                                }
                                .font(.system(size: 10.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(6)
                                .buttonStyle(.plain)
                                
                                Button("确认清空") {
                                    storage.clearUnpinned()
                                    SoundManager.shared.playDelete()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        showClearConfirm = false
                                    }
                                    Task { await refreshFootprint() }
                                }
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(6)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .task(id: storage.items.count) {
            await refreshFootprint()
        }
    }
    
    private func refreshFootprint() async {
        let stats = await storage.computeStorageFootprintAsync()
        diskBytes = stats.totalBytes
        imageFileCount = stats.imageCount
        isCalculatingFootprint = false
    }
    
    private func storageMetricCard(icon: String, color: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
