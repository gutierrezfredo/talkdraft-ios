import SwiftUI

struct OnboardingCategoriesStep: View {
    @Binding var selectedIndices: Set<Int>
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("What do you want to capture?")
                    .font(.brandTitle)
                    .fontDesign(nil)

                Text("Pick a few to get started. You can always add more later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            Spacer()

            // Category chips — matching app's CategoryChip style
            FlowLayout(spacing: 10) {
                ForEach(Array(CategorySuggestion.all.enumerated()), id: \.offset) { index, suggestion in
                    let isSelected = selectedIndices.contains(index)
                    let chipColor = Color.categoryColor(hex: suggestion.color)

                    Button {
                        withAnimation(.snappy) {
                            if isSelected {
                                selectedIndices.remove(index)
                            } else {
                                selectedIndices.insert(index)
                            }
                        }
                    } label: {
                        Text(suggestion.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(chipColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.darkSurface : .white)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? chipColor : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Text("Choose as many as you want.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 40)

            Spacer()

            // CTAs
            Button {
                onNext()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 8)
        }
        .sensoryFeedback(.selection, trigger: selectedIndices.count)
    }
}

// MARK: - Category Suggestions

struct CategorySuggestion {
    let name: String
    let color: String

    static let all: [CategorySuggestion] = [
        CategorySuggestion(name: "Ideas", color: "#6366F1"),
        CategorySuggestion(name: "Action Items", color: "#EF4444"),
        CategorySuggestion(name: "Journal", color: "#10B981"),
        CategorySuggestion(name: "Meetings", color: "#F59E0B"),
        CategorySuggestion(name: "Goals", color: "#14B8A6"),
        CategorySuggestion(name: "Work", color: "#3B82F6"),
        CategorySuggestion(name: "Personal", color: "#EC4899"),
        CategorySuggestion(name: "Content Ideas", color: "#8B5CF6"),
        CategorySuggestion(name: "Reminders", color: "#F97316"),
        CategorySuggestion(name: "Travel", color: "#0EA5E9"),
        CategorySuggestion(name: "Brain Dumps", color: "#A855F7"),
        CategorySuggestion(name: "Daily Reflections", color: "#06B6D4"),
    ]
}
