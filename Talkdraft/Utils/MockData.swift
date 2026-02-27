import Foundation

enum MockData {
    static let categories: [Category] = [
        Category(id: UUID(), name: "Ideas", color: "#3B82F6", icon: nil, sortOrder: 0, createdAt: .now),
        Category(id: UUID(), name: "Work", color: "#EF4444", icon: nil, sortOrder: 1, createdAt: .now),
        Category(id: UUID(), name: "Personal", color: "#10B981", icon: nil, sortOrder: 2, createdAt: .now),
        Category(id: UUID(), name: "Grocery List", color: "#F59E0B", icon: nil, sortOrder: 3, createdAt: .now),
    ]

    static var notes: [Note] {
        let ideas = categories[0].id
        let work = categories[1].id
        let personal = categories[2].id

        return [
            Note(
                id: UUID(),
                categoryId: ideas,
                title: "App redesign concept",
                content: "What if we used a card-based layout with subtle gradients? Could give it a more premium feel without being too heavy.",
                source: .voice,
                audioUrl: "mock",
                durationSeconds: 45,
                createdAt: Date(),
                updatedAt: Date()
            ),
            Note(
                id: UUID(),
                categoryId: work,
                title: "Meeting notes",
                content: "Discussed Q2 roadmap. Need to prioritize the translation feature and get the iOS app shipped by end of March.",
                source: .voice,
                durationSeconds: 120,
                createdAt: Date().addingTimeInterval(-3600),
                updatedAt: Date().addingTimeInterval(-3600)
            ),
            Note(
                id: UUID(),
                categoryId: personal,
                title: nil,
                content: "Remember to call mom about the weekend plans. She mentioned something about a family dinner on Saturday.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date().addingTimeInterval(-86400)
            ),
            Note(
                id: UUID(),
                categoryId: ideas,
                title: "Podcast episode idea",
                content: "Episode about how voice interfaces are changing the way we interact with technology. Interview someone from the Speech team.",
                source: .voice,
                durationSeconds: 30,
                createdAt: Date().addingTimeInterval(-86400 * 2),
                updatedAt: Date().addingTimeInterval(-86400 * 2)
            ),
            Note(
                id: UUID(),
                title: "Quick thought",
                content: "The best ideas come when you're not trying to have them.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400 * 3),
                updatedAt: Date().addingTimeInterval(-86400 * 3)
            ),
            Note(
                id: UUID(),
                categoryId: work,
                title: "Bug report",
                content: "Audio playback cuts out when switching between notes quickly. Need to investigate AVAudioSession management.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400 * 5),
                updatedAt: Date().addingTimeInterval(-86400 * 5)
            ),
            Note(
                id: UUID(),
                categoryId: personal,
                title: "Book recommendations",
                content: "Check out Atomic Habits by James Clear and Deep Work by Cal Newport. Both recommended by multiple people this week.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400 * 6),
                updatedAt: Date().addingTimeInterval(-86400 * 6)
            ),
            Note(
                id: UUID(),
                categoryId: ideas,
                title: "Voice journal feature",
                content: "What if users could set a daily reminder to record a voice journal entry? Auto-transcribe and tag by mood.",
                source: .voice,
                durationSeconds: 55,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                updatedAt: Date().addingTimeInterval(-86400 * 7)
            ),
            Note(
                id: UUID(),
                categoryId: work,
                title: "Sprint retro notes",
                content: "Velocity improved 15% this sprint. Main blocker was the auth migration. Need to timebox research tasks better.",
                source: .voice,
                durationSeconds: 180,
                createdAt: Date().addingTimeInterval(-86400 * 8),
                updatedAt: Date().addingTimeInterval(-86400 * 8)
            ),
            Note(
                id: UUID(),
                categoryId: personal,
                title: "Recipe — pasta aglio e olio",
                content: "Garlic, olive oil, chili flakes, parsley, spaghetti. Cook garlic low and slow. Save pasta water for emulsion.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400 * 9),
                updatedAt: Date().addingTimeInterval(-86400 * 9)
            ),
            Note(
                id: UUID(),
                categoryId: ideas,
                title: "Collaboration mode",
                content: "Shared notebooks where multiple people can add voice notes to the same category. Like a shared brain dump space.",
                source: .voice,
                durationSeconds: 40,
                createdAt: Date().addingTimeInterval(-86400 * 10),
                updatedAt: Date().addingTimeInterval(-86400 * 10)
            ),
            Note(
                id: UUID(),
                title: "Random thought",
                content: "The gap between knowing what to do and actually doing it is where most people get stuck.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400 * 11),
                updatedAt: Date().addingTimeInterval(-86400 * 11)
            ),
            Note(
                id: UUID(),
                categoryId: work,
                title: "API rate limits",
                content: "Groq free tier is 30 requests per minute. Need to add queuing or switch to a paid plan before launch.",
                source: .text,
                createdAt: Date().addingTimeInterval(-86400 * 12),
                updatedAt: Date().addingTimeInterval(-86400 * 12)
            ),
        ]
    }
}
