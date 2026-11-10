import Foundation
import SwiftUI

public enum ClipType: String, Codable, CaseIterable {
    case text
    case image
    case color
    case url
    case file
    
    public var title: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .color: return "颜色"
        case .url: return "链接"
        case .file: return "文件"
        }
    }
    
    public var iconName: String {
        switch self {
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        case .color: return "paintpalette.fill"
        case .url: return "link"
        case .file: return "folder.fill"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .text: return Color.blue
        case .image: return Color.purple
        case .color: return Color.orange
        case .url: return Color.teal
        case .file: return Color.green
        }
    }
}

public enum ClipFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case color = "颜色"
    case url = "链接"
    case file = "文件"
    case pinned = "收藏"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "tray.2.fill"
        case .text: return "text.alignleft"
        case .image: return "photo.fill"
        case .color: return "paintpalette.fill"
        case .url: return "link"
        case .file: return "folder.fill"
        case .pinned: return "star.fill"
        }
    }
}
