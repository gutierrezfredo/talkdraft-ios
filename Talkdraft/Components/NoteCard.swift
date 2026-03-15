import SwiftUI

struct NoteCard: View {
    let note: Note
    let category: Category?
    var content: String? = nil
    var selectionMode: Bool = false
    var isSelected: Bool = false

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var transcribingPulse = false
    @State private var rewritePulse = false

    private var isDark: Bool { colorScheme == .dark }
    private var resolvedContent: String { content ?? note.content }
    private var previewContent: String { NoteTextFormatting.plainDisplayText(for: resolvedContent) }
    private var bodyState: NoteBodyState { NoteBodyState(content: resolvedContent, source: note.source) }
    private var isRewriting: Bool { noteStore.activeRewriteIds.contains(note.id) }

    private var cardBackground: Color {
        guard let category else {
            return isDark ? .darkBackground : .white
        }
        return Color(hex: category.color)
            .blended(opacity: 0.14, isDark: isDark)
    }

    private var actionItemCounts: (completed: Int, total: Int)? {
        let checked = resolvedContent.filter { $0 == "☑" }.count
        let unchecked = resolvedContent.filter { $0 == "☐" }.count
        let total = checked + unchecked
        guard total > 0 else { return nil }
        return (checked, total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Date & action items
            HStack(spacing: 4) {
                Text(note.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let counts = actionItemCounts {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 2) {
                        Image(systemName: counts.completed == counts.total ? "checkmark.circle.fill" : "circle")
                        Text("\(counts.completed)/\(counts.total)")
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(counts.completed == counts.total ? .secondary : Color.brand)
                }
            }

            // Title
            if let title = note.title, !title.isEmpty {
                Text(title)
                    .font(.brandTitle3)
                    .fontWeight(.regular)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            // Content preview
            if bodyState == .transcribing {
                Text(NoteBodyState.transcribingPlaceholder)
                    .italic()
                    .font(.caption)
                    .foregroundStyle(Color.brand)
                    .opacity(transcribingPulse ? 0.35 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            transcribingPulse = true
                        }
                    }
                    .onDisappear { transcribingPulse = false }
            } else if isRewriting {
                Label("Rewriting…", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(Color.brand)
                    .opacity(rewritePulse ? 0.35 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                            rewritePulse = true
                        }
                    }
                    .onDisappear { rewritePulse = false }
            } else {
                Text(previewContent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            // Footer
            if let category {
                Text(category.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.categoryColor(hex: category.color))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isDark ? Color.darkBackground : .white)
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
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
                .strokeBorder(
                    isSelected ? Color.brand
                        : (category == nil ? (isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)) : .clear),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
    }
}
