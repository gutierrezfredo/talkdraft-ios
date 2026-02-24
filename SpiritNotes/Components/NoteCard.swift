import SwiftUI

struct NoteRow: View {
    let note: Note
    let category: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let title = note.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                if note.source == .voice {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(note.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text(note.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let category {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label(category.name, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: category.color))
                }

                if let duration = note.durationSeconds {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(formattedDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
