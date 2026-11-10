import Foundation
import SwiftUI

public struct ClipGroup: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var colorHex: String?
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        colorHex: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}
