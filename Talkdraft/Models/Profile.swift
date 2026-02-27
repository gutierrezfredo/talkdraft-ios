import Foundation

struct Profile: Codable, Sendable {
    let id: UUID
    var displayName: String?
    var plan: Plan
    let createdAt: Date
    var deletionScheduledAt: Date?
    var language: String?

    enum Plan: String, Codable, Sendable {
        case free
        case pro
    }
}
