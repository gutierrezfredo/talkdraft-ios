import SwiftUI

struct RecordView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = AudioRecorder()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCancelConfirmation = false
    @State private var multiSpeaker = false
    @State private var showBackgroundBanner = false
    @State private var startTask: Task<Void, Never>?
    let categoryId: UUID?
    var onNoteSaved: ((Note) -> Void)?

    private let maxDurationSeconds = 3600

    var body: some View {
        ZStack {
            Group {
                if colorScheme == .dark {
                    Color.darkBackground
                } else {
                    LinearGradient(
                        colors: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
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

                // Multi-speaker toggle
                Toggle(isOn: $multiSpeaker) {
                    Label("Multi-speaker", systemImage: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
                .tint(colorScheme == .dark ? Color.brand : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .fixedSize()
                .contentShape(Capsule())
                .padding(.bottom, 72)

                // Controls
                controls
                    .padding(.bottom, 48)
            }

            if showBackgroundBanner {
                VStack {
                    BackgroundRecordingBanner()
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.snappy, value: showBackgroundBanner)
            }
        }
        .interactiveDismissDisabled(recorder.elapsedSeconds >= 1)
        .alert("Cancel Recording?", isPresented: $showCancelConfirmation) {
            Button("Cancel Recording", role: .destructive) {
                cancelPendingStart()
                recorder.cancelRecording()
                dismiss()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("Your recording will be lost.")
        }
        .alert("Recording Error", isPresented: $showError) {
            Button("OK") {
                if !recorder.isRecording {
                    scheduleRecordingStart()
                }
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            scheduleRecordingStart()
        }
        .onDisappear {
            cancelPendingStart()
        }
        .onChange(of: recorder.elapsedSeconds) { _, elapsed in
            if Int(elapsed) >= maxDurationSeconds && recorder.isRecording {
                stopAndSave()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                recorder.handleEnteredBackground()
            case .active:
                recorder.handleReturnedToForeground()
                if recorder.didRecordInBackground {
                    withAnimation(.snappy) { showBackgroundBanner = true }
                    recorder.clearBackgroundIndicator()
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeOut) { showBackgroundBanner = false }
                    }
                }
            default:
                break
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
        .sensoryFeedback(.selection, trigger: recorder.isPaused)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") {
                if recorder.elapsedSeconds >= 1 {
                    showCancelConfirmation = true
                } else {
                    recorder.cancelRecording()
                    dismiss()
                }
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
        HStack(spacing: 0) {
            ForEach(Array(formattedTime.enumerated()), id: \.offset) { _, char in
                if char == ":" {
                    Text(":")
                        .font(.custom("Bricolage Grotesque", size: 88).weight(.light))
                        .fontDesign(nil)
                } else {
                    ZStack {
                        Text("0").opacity(0) // widest reference
                        Text(String(char))
                            .transition(.blurFade)
                            .id(char)
                    }
                    .font(.custom("Bricolage Grotesque", size: 88).weight(.light))
                    .fontDesign(nil)
                    .animation(.easeInOut(duration: 0.25), value: char)
                }
            }
        }
        .foregroundStyle(.white)
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
                    .fontWeight(.semibold)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.brand)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)

            // Stop (save)
            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
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
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if recorder.isPaused {
                    recorder.resumeRecording()
                } else {
                    recorder.pauseRecording()
                }
            } label: {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.brand)
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

    private func scheduleRecordingStart() {
        cancelPendingStart(discardPreparedSession: false)
        startTask = Task { @MainActor in
            if !AudioRecorder.currentRouteUsesCarAudio() {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            startRecording()
        }
    }

    private func cancelPendingStart(discardPreparedSession: Bool = true) {
        startTask?.cancel()
        startTask = nil
        if discardPreparedSession, !recorder.isRecording {
            Task { @MainActor in
                AudioRecorder.discardPreparedRecordingSession()
            }
        }
    }

    private func startRecording() {
        startTask = nil
        Task { @MainActor in
            do {
                try await recorder.startRecording()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func stopAndSave() {
        cancelPendingStart()
        let duration = recorder.elapsedSeconds

        guard duration >= 1 else {
            recorder.cancelRecording()
            dismiss()
            return
        }

        guard let audioURL = recorder.stopRecording() else { return }
        let userId = authStore.userId
        let language = settingsStore.language == "auto" ? nil : settingsStore.language

        let noteId = UUID()
        let note = Note(
            id: noteId,
            userId: userId,
            categoryId: categoryId,
            title: nil,
            content: "",
            source: .voice,
            audioUrl: audioURL.absoluteString,
            durationSeconds: Int(duration),
            createdAt: Date(),
            updatedAt: Date()
        )
        noteStore.addNote(note)
        noteStore.setNoteBodyState(id: noteId, state: .transcribing)

        // Transcribe in background
        Task { @MainActor in
            noteStore.transcribeNote(id: noteId, audioFileURL: audioURL, language: language, userId: userId, customDictionary: settingsStore.customDictionary, multiSpeaker: multiSpeaker)
        }

        onNoteSaved?(note)
        dismiss()
    }
}

// MARK: - Record Toggle Style

private struct RecordToggleStyle: ToggleStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn
                        ? (colorScheme == .dark ? Color.brand : .white)
                        : Color.white.opacity(0.25)
                    )
                    .frame(width: 50, height: 30)

                Circle()
                    .fill(configuration.isOn
                        ? (colorScheme == .dark ? .white : Color.brand)
                        : .white
                    )
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
            .animation(.snappy(duration: 0.2), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
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

// MARK: - Blur Fade Transition

private struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

private extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: 6, opacity: 0),
            identity: BlurFadeModifier(radius: 0, opacity: 1)
        )
    }
}
