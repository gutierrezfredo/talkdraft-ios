import AVFoundation
import Testing
@testable import Talkdraft

@Test func appLaunches() async throws {
    #expect(Bool(true))
}

@Test func audioCompressorWrites16kMonoOutput() async throws {
    let sourceURL = try makeSineWaveFile()
    let compressedURL = try await AudioCompressor.compress(sourceURL: sourceURL)
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        AudioCompressor.cleanup(compressedURL)
    }

    let compressedFile = try AVAudioFile(forReading: compressedURL)

    #expect(FileManager.default.fileExists(atPath: compressedURL.path))
    #expect(abs(compressedFile.fileFormat.sampleRate - 16_000) < 0.5)
    #expect(compressedFile.fileFormat.channelCount == 1)
}

@MainActor
@Test func audioPlayerPreloadsAndSeeksLocalAudio() async throws {
    let sourceURL = try makeSineWaveFile(duration: 1.0)
    let player = AudioPlayer()
    defer {
        player.stop()
        try? FileManager.default.removeItem(at: sourceURL)
    }

    player.preload(url: sourceURL)
    for _ in 0..<40 {
        if player.duration > 0 {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(player.duration > 0)

    player.play(url: sourceURL)
    #expect(player.isPlaying)

    let midpoint = player.duration * 0.5
    player.seek(to: midpoint)
    #expect(abs(player.currentTime - midpoint) < 0.1)

    player.pause()
    #expect(!player.isPlaying)
}

@MainActor
@Test func audioRecorderSupportsPauseResumeAndCancel() throws {
    let recorder = AudioRecorder()

    try recorder.startRecording()
    #expect(recorder.isRecording)
    #expect(!recorder.isPaused)

    recorder.pauseRecording()
    #expect(recorder.isPaused)

    recorder.resumeRecording()
    #expect(recorder.isRecording)
    #expect(!recorder.isPaused)

    recorder.cancelRecording()
    #expect(!recorder.isRecording)
    #expect(!recorder.isPaused)
    #expect(recorder.elapsedSeconds == 0)
}

@MainActor
@Test func noteStoreImportAudioNoteCopiesAndTranscribesImportedAudio() async throws {
    let sourceURL = try makeSineWaveFile(duration: 0.6)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let store = NoteStore(
        transcriptionConnectivityProbe: {},
        transcriptionUploadExecutor: { request in
            #expect(!request.audioData.isEmpty)
            #expect(request.fileName.hasSuffix(".m4a"))
            #expect(request.language == "en")
            return TranscriptionResult(
                text: "Imported transcript",
                language: "en",
                audioUrl: "https://example.com/audio/imported.m4a",
                durationSeconds: 2
            )
        },
        aiTitleExecutor: { _, _ in
            "Imported title"
        }
    )

    let note = try await store.importAudioNote(
        from: sourceURL,
        userId: nil,
        categoryId: nil,
        language: "en",
        requiresSecurityScopedAccess: false
    )

    for _ in 0..<60 {
        if let updated = store.notes.first(where: { $0.id == note.id }),
           updated.content == "Imported transcript",
           updated.audioUrl == "https://example.com/audio/imported.m4a",
           updated.title == "Imported title" {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    guard let updated = store.notes.first(where: { $0.id == note.id }) else {
        Issue.record("Expected imported note to remain in the store")
        return
    }

    #expect(updated.source == .voice)
    #expect(updated.content == "Imported transcript")
    #expect(updated.language == "en")
    #expect(updated.audioUrl == "https://example.com/audio/imported.m4a")
    #expect(updated.durationSeconds == 2)
    #expect(updated.title == "Imported title")
}

private func makeSineWaveFile(
    sampleRate: Double = 44_100,
    duration: Double = 0.35,
    frequency: Double = 440
) throws -> URL {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let samples = buffer.floatChannelData![0]
    for frame in 0..<Int(frameCount) {
        let sampleTime = Double(frame) / sampleRate
        samples[frame] = Float(sin(2 * .pi * frequency * sampleTime) * 0.25)
    }

    let file = try AVAudioFile(
        forWriting: outputURL,
        settings: format.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)

    return outputURL
}
