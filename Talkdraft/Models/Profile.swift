import Foundation

struct Profile: Codable, Sendable {
    let id: UUID
    var displayName: String?
    var plan: Plan
    let createdAt: Date
    var deletionScheduledAt: Date?
    var language: String?
    var customDictionary: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case plan
        case createdAt = "created_at"
        case deletionScheduledAt = "deletion_scheduled_at"
        case language
        case customDictionary = "custom_dictionary"
    }

    enum Plan: String, Codable, Sendable {
        case free
        case pro
    }
}
