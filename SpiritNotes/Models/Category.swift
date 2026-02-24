import Foundation

struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String
    var icon: String?
    var sortOrder: Int
    let createdAt: Date
}
