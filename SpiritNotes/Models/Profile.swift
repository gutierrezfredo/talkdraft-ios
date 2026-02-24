import Foundation

struct Profile: Codable {
    let userId: UUID
    var displayName: String?
    var plan: Plan
    let createdAt: Date
    var deletionScheduledAt: Date?
    var language: String?

    enum Plan: String, Codable {
        case free
        case pro
    }
}
