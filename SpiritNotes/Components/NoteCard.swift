import SwiftUI

struct NoteCard: View {
    let note: Note
    let category: Category?

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var cardBackground: Color {
        guard let category else {
            return isDark ? Color(hex: "#111111") : .white
        }
        return Color(hex: category.color)
            .blended(opacity: isDark ? 0.10 : 0.14, isDark: isDark)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Date
            Text(note.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Title
            if let title = note.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            // Content preview
            Text(note.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            // Footer
            if let category {
                Text(category.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: category.color))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isDark ? Color(hex: "#1f1f1f") : .white)
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

}
