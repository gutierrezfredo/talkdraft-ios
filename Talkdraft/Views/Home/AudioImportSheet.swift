import SwiftUI

struct AudioImportSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("importMultiSpeaker") private var multiSpeaker = false

    let fileName: String
    let onImport: (Bool) -> Void

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.25) : .secondary.opacity(0.3)
    }

    var body: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Audio")
                    .font(.brandTitle2)
                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: $multiSpeaker) {
                Label("Multi-speaker", systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .toggleStyle(.switch)
            .tint(Color.brand)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Capsule())

            Button {
                onImport(multiSpeaker)
            } label: {
                Text("Import")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.brand))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }
}
