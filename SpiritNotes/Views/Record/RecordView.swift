import SwiftUI

struct RecordView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var recorder = AudioRecorder()
    @State private var showError = false
    @State private var errorMessage = ""

    let categoryId: UUID?
    @State private var savedNote: Note?

    private let maxDurationSeconds = 180 // 3 min free

    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.darkBackground : Color.brand)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    header
                        .padding(.top, 16)

                    Spacer()

                    // Timer
                    timer
                        .padding(.bottom, 8)

                    // Max duration label
                    Text("Max \(formattedDuration(maxDurationSeconds))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 48)

                    // Audio level bars
                    AudioLevelBars(
                        bands: recorder.frequencyBands,
                        isActive: recorder.isRecording && !recorder.isPaused,
                        barColor: colorScheme == .dark ? .brand : .white
                    )
                    .frame(height: 140)
                    .padding(.horizontal, 24)

                    Spacer()

                    // Controls
                    controls
                        .padding(.bottom, 48)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $savedNote) { note in
                NoteDetailView(note: note)
            }
        }
        .alert("Recording Error", isPresented: $showError) {
            Button("OK") { dismiss() }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            startRecording()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
        .sensoryFeedback(.selection, trigger: recorder.isPaused)
        .onChange(of: savedNote) { _, newValue in
            if newValue == nil && !recorder.isRecording {
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") {
                recorder.cancelRecording()
                dismiss()
            }
            .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text("Record")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            // Balance spacer
            Text("Cancel").opacity(0)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Timer

    private var timer: some View {
        Text(formattedTime)
            .font(.system(size: 72, weight: .light, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .contentTransition(.numericText())
            .opacity(recorder.isPaused ? 0.5 : 1.0)
            .animation(
                recorder.isPaused
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: recorder.isPaused
            )
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 40) {
            // Restart
            Button {
                recorder.cancelRecording()
                startRecording()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Stop (save)
            Button {
                stopAndSave()
            } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.brand)
                    .frame(width: 28, height: 28)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(.white))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Pause / Resume
            Button {
                if recorder.isPaused {
                    recorder.resumeRecording()
                } else {
                    recorder.pauseRecording()
                }
            } label: {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        formattedDuration(Int(recorder.elapsedSeconds))
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startRecording() {
        do {
            try recorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func stopAndSave() {
        guard let audioURL = recorder.stopRecording() else { return }
        let duration = recorder.elapsedSeconds
        let userId = authStore.user?.id
        let language = settingsStore.language == "auto" ? nil : settingsStore.language

        let noteId = UUID()
        let note = Note(
            id: noteId,
            userId: userId,
            categoryId: categoryId,
            title: nil,
            content: "Transcribing…",
            source: .voice,
            audioUrl: audioURL.absoluteString,
            durationSeconds: Int(duration),
            createdAt: Date(),
            updatedAt: Date()
        )
        noteStore.addNote(note)

        // Transcribe in background
        Task.detached {
            await MainActor.run { noteStore.transcribeNote(id: noteId, audioFileURL: audioURL, language: language, userId: userId) }
        }

        savedNote = note
    }
}

// MARK: - Audio Level Bars

private struct AudioLevelBars: View {
    let bands: [Float]
    let isActive: Bool
    var barColor: Color = .white

    private let barWidth: CGFloat = 8
    private let barSpacing: CGFloat = 6
    private let maxHeight: CGFloat = 140
    private let minHeight: CGFloat = 3

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<bands.count, id: \.self) { index in
                let level = isActive ? CGFloat(bands[index]) : 0
                let height = minHeight + level * (maxHeight - minHeight)

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(barColor)
                    .frame(width: barWidth, height: max(minHeight, min(maxHeight, height)))
                    .animation(.easeOut(duration: 0.08), value: bands[index])
            }
        }
    }
}
