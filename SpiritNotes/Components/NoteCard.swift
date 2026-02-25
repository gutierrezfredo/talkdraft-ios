import SwiftUI

struct NoteCard: View {
    let note: Note
    let category: Category?
    var selectionMode: Bool = false
    var isSelected: Bool = false

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
                            .fill(isDark ? Color.darkBackground : .white)
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
        .overlay(alignment: .topTrailing) {
            if selectionMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.brand : Color.clear)
                        .frame(width: 24, height: 24)

                    Circle()
                        .strokeBorder(
                            isSelected ? Color.brand : (isDark ? Color(hex: "#525252") : Color(hex: "#d4d4d4")),
                            lineWidth: 2
                        )
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? Color.brand : .clear, lineWidth: 2)
        )
    }
}
