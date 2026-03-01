import SwiftUI

struct RecentlyDeletedView: View {
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var noteToDelete: Note?

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
    }

    var body: some View {
        Group {
            if noteStore.deletedNotes.isEmpty {
                ContentUnavailableView(
                    "No Deleted Notes",
                    systemImage: "trash.slash",
                    description: Text("Deleted notes appear here for 30 days before being permanently removed.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(noteStore.deletedNotes) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(note.title ?? "Untitled")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer()

                                    if let deletedAt = note.deletedAt {
                                        Text(daysRemaining(from: deletedAt))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(note.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                HStack(spacing: 12) {
                                    Button {
                                        withAnimation(.snappy) {
                                            noteStore.restoreNote(id: note.id)
                                        }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.brand)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Button(role: .destructive) {
                                        noteToDelete = note
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(cardColor)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Forever?", isPresented: .init(
            get: { noteToDelete != nil },
            set: { if !$0 { noteToDelete = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let note = noteToDelete {
                    withAnimation(.snappy) {
                        noteStore.permanentlyDeleteNote(id: note.id)
                    }
                }
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: {
            Text("This note will be permanently deleted. This can't be undone.")
        }
    }

    private func daysRemaining(from deletedAt: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        let remaining = max(30 - days, 0)
        return "\(remaining)d left"
    }
}
