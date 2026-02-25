import Foundation

struct Category: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var userId: UUID?
    var name: String
    var color: String
    var icon: String?
    var sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case color
        case icon
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}
