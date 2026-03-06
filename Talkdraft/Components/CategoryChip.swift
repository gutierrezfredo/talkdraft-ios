import SwiftUI

struct CategoryChip: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(name)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 200)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.darkSurface : .white)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            )
            .contentShape(Capsule())
            .contentShape(.dragPreview, Capsule())
            .onTapGesture(perform: action)
            .sensoryFeedback(.selection, trigger: isSelected)
    }
}
