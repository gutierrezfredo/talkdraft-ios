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
        ]
    }
}
