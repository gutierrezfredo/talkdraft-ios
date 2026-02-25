import SwiftUI

struct CategoryChip: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.darkSurface : .white)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
