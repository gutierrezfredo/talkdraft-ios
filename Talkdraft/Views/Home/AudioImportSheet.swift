import SwiftUI

struct AudioImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("importMultiSpeaker") private var multiSpeaker = false

    let fileName: String
    let onImport: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
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
                    .font(.body)
            }
            .tint(Color.brand)

            Button {
                dismiss()
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
        .padding(.top, 24)
    }
}
