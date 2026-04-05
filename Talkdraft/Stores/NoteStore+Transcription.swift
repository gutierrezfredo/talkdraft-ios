import Foundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

extension NoteStore {
    private enum TranscriptionFallbackReason {
        case shortRecording
        case lowSpeech

        var errorType: String {
            switch self {
            case .shortRecording:
                return "transcription_short_fallback"
            case .lowSpeech:
                return "transcription_low_speech_fallback"
            }
        }

        var errorMessage: String {
            switch self {
            case .shortRecording:
                return "Replaced likely hallucinated short transcription with fallback copy"
            case .lowSpeech:
                return "Replaced likely non-speech hallucination with fallback copy"
            }
        }
    }

    // MARK: - Transcription

    func transcribeNote(id: UUID, audioFileURL: URL, language: String?, userId: UUID?, customDictionary: [String] = [], multiSpeaker: Bool = false) {
        guard activeTranscriptionIds.insert(id).inserted else {
            logger.info("Skipping duplicate transcription start for \(id)")
            return
        }

        // Persist the local file path so it survives app restarts
        registerLocalAudio(audioFileURL, for: id)
        setNoteBodyState(id: id, state: .transcribing)

        Task {
            defer { self.activeTranscriptionIds.remove(id) }
            var compressedURL: URL?
            defer { if let compressedURL { AudioCompressor.cleanup(compressedURL) } }

            do {
                let signalAnalysis = try? await AudioSignalAnalyzer.analyze(url: audioFileURL)

                // Validate audio file before processing
                guard FileManager.default.fileExists(atPath: audioFileURL.path),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path),
                      let fileSize = attrs[.size] as? Int, fileSize > 0
                else {
                    logger.error("transcribeNote: audio file missing or empty at \(audioFileURL.path)")
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_failed",
                        message: "Audio file missing or empty",
                        context: ["note_id": id.uuidString, "path": audioFileURL.lastPathComponent],
                        userId: userId
                    )
                    return
                }

                if let analysis = signalAnalysis,
                   AudioSignalAnalyzer.shouldTreatAsSilent(analysis) {
                    logger.info(
                        "transcribeNote: skipping transcription for quiet audio note=\(id) duration=\(analysis.durationSeconds, privacy: .public) peak=\(analysis.peakAmplitude, privacy: .public) rms=\(analysis.rmsAmplitude, privacy: .public)"
                    )
                    guard var note = notes.first(where: { $0.id == id }) else { return }
                    let fallbackMessage = TranscriptionService.nextNoSpeechFallbackText()
                    setLocalVoiceBodyState(nil, for: id)
                    note.content = fallbackMessage
                    note.updatedAt = Date()
                    updateNote(note)
                    ErrorLogger.shared.log(
                        type: "transcription_silent_fallback",
                        message: "Skipped transcription for near-silent recording",
                        context: [
                            "note_id": id.uuidString,
                            "duration_seconds": String(Int(analysis.durationSeconds)),
                            "peak_amplitude": String(analysis.peakAmplitude),
                            "rms_amplitude": String(analysis.rmsAmplitude)
                        ],
                        userId: userId
                    )
                    return
                }

                // Connectivity probe — quick request to verify network before heavy upload
                do {
                    try await transcriptionConnectivityProbe()
                } catch {
                    logger.info("Connectivity probe failed — device appears offline: \(error)")
                    setNoteBodyState(id: id, state: .waitingForConnection)
                    return
                }

                // Always upload original for storage quality; compress separately for Whisper
                let audioData = try Data(contentsOf: audioFileURL)
                let fileName = audioFileURL.lastPathComponent

                var whisperData: Data? = nil
                var whisperFileName: String? = nil
                do {
                    let compressed = try await AudioCompressor.compress(sourceURL: audioFileURL)
                    compressedURL = compressed
                    whisperData = try Data(contentsOf: compressed)
                    whisperFileName = compressed.lastPathComponent
                } catch {
                    logger.warning("Compression failed, Whisper will use original: \(error)")
                }

                let timeoutSeconds = transcriptionTimeoutSeconds(for: id)
                let request = TranscriptionUploadRequest(
                    audioData: audioData,
                    fileName: fileName,
                    language: language,
                    userId: userId,
                    customDictionary: customDictionary,
                    whisperData: whisperData,
                    whisperFileName: whisperFileName,
                    multiSpeaker: multiSpeaker
                )
                let result = try await performTranscriptionWithTimeout(seconds: timeoutSeconds) {
                    try await self.transcriptionUploadExecutor(request)
                }

                // Guard against empty transcription
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    logger.warning("transcribeNote: received empty transcription for \(id)")
                    guard var note = notes.first(where: { $0.id == id }) else {
                        logger.error("transcribeNote: note \(id) not found in local store after empty transcription")
                        await deleteRemoteAudioIfNeeded(for: result.audioUrl, noteId: id, reason: "missing_note_after_empty_transcription")
                        return
                    }

                    let fallbackMessage = TranscriptionService.nextNoSpeechFallbackText()
                    setLocalVoiceBodyState(nil, for: id)
                    note.content = fallbackMessage
                    note.language = result.language
                    if let audioUrl = result.audioUrl {
                        note.audioUrl = audioUrl
                    }
                    if let duration = result.durationSeconds {
                        note.durationSeconds = duration
                    }
                    note.updatedAt = Date()
                    updateNote(note)

                    if result.audioUrl != nil {
                        unregisterLocalAudio(for: id)
                        try? FileManager.default.removeItem(at: audioFileURL)
                    }

                    ErrorLogger.shared.log(
                        type: "transcription_empty_fallback",
                        message: "Replaced empty transcription with fallback copy",
                        context: [
                            "note_id": id.uuidString,
                            "language": language ?? "auto",
                            "duration_seconds": String(result.durationSeconds ?? 0),
                            "has_remote_audio": String(result.audioUrl != nil)
                        ],
                        userId: userId
                    )
                    return
                }

                // Update note with transcription
                guard var note = notes.first(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after transcription")
                    await deleteRemoteAudioIfNeeded(for: result.audioUrl, noteId: id, reason: "missing_note_after_transcription")
                    return
                }
                let transcriptionDuration = TimeInterval(note.durationSeconds ?? result.durationSeconds ?? 0)
                let fallbackReason = transcriptionFallbackReason(
                    for: transcribedText,
                    durationSeconds: transcriptionDuration,
                    signalAnalysis: signalAnalysis,
                    speechMetrics: result.speechMetrics
                )
                let finalContent: String
                let initialSpeakerNames: [String: String]?
                if let fallbackReason {
                    finalContent = TranscriptionService.nextNoSpeechFallbackText()
                    initialSpeakerNames = nil
                    logTranscriptionFallback(
                        fallbackReason,
                        noteId: id,
                        durationSeconds: transcriptionDuration,
                        transcribedText: transcribedText,
                        signalAnalysis: signalAnalysis,
                        speechMetrics: result.speechMetrics,
                        userId: userId
                    )
                } else {
                    let formatted = Self.formatMultiSpeakerTranscript(transcribedText)
                    finalContent = formatted.content
                    initialSpeakerNames = formatted.speakerNames
                }
                setLocalVoiceBodyState(nil, for: id)
                note.content = finalContent
                if let initialSpeakerNames { note.speakerNames = initialSpeakerNames }
                note.language = result.language
                if let audioUrl = result.audioUrl {
                    note.audioUrl = audioUrl
                }
                if let duration = result.durationSeconds {
                    note.durationSeconds = duration
                }
                note.updatedAt = Date()
                updateNote(note)

                // Clean up local audio file after remote URL confirmed
                if result.audioUrl != nil {
                    unregisterLocalAudio(for: id)
                    try? FileManager.default.removeItem(at: audioFileURL)
                }

                // Generate AI title in background
                if fallbackReason == nil {
                    generateTitle(for: id, content: transcribedText, language: result.language)
                }
            } catch {
                logger.error("transcribeNote failed for \(id): \(error)")
                guard notes.contains(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after failure")
                    return
                }

                let fileSizeMB = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? Int)
                    .map { String(format: "%.1f", Double($0) / 1_048_576.0) } ?? "?"

                if error is URLError {
                    setNoteBodyState(id: id, state: .waitingForConnection)
                    ErrorLogger.shared.log(
                        type: "transcription_offline",
                        message: "Network unavailable during transcription",
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB],
                        userId: userId
                    )
                } else if let timeoutError = error as? TranscriptionWorkflowError {
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_timeout",
                        message: timeoutError.localizedDescription,
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB, "language": language ?? "auto"],
                        userId: userId
                    )
                } else {
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_failed",
                        message: error.localizedDescription,
                        context: ["note_id": id.uuidString, "file_size_mb": fileSizeMB, "language": language ?? "auto"],
                        userId: userId
                    )
                }
            }
        }
    }

    func transcriptionRepairThresholdSeconds(for note: Note) -> TimeInterval {
        transcriptionTimeoutSeconds(for: note.durationSeconds) + 30
    }

    private func transcriptionTimeoutSeconds(for noteId: UUID) -> TimeInterval {
        transcriptionTimeoutSeconds(for: notes.first(where: { $0.id == noteId })?.durationSeconds)
    }

    private func transcriptionFallbackReason(
        for transcribedText: String,
        durationSeconds: TimeInterval,
        signalAnalysis: AudioSignalAnalysis?,
        speechMetrics: TranscriptionSpeechMetrics?
    ) -> TranscriptionFallbackReason? {
        if TranscriptionService.shouldUseShortRecordingFallback(
            for: transcribedText,
            durationSeconds: durationSeconds
        ) {
            return .shortRecording
        }

        if TranscriptionService.shouldUseLowSpeechFallback(
            for: transcribedText,
            analysis: signalAnalysis,
            speechMetrics: speechMetrics
        ) {
            return .lowSpeech
        }

        return nil
    }

    private func logTranscriptionFallback(
        _ reason: TranscriptionFallbackReason,
        noteId: UUID,
        durationSeconds: TimeInterval,
        transcribedText: String,
        signalAnalysis: AudioSignalAnalysis?,
        speechMetrics: TranscriptionSpeechMetrics?,
        userId: UUID?
    ) {
        ErrorLogger.shared.log(
            type: reason.errorType,
            message: reason.errorMessage,
            context: transcriptionFallbackContext(
                noteId: noteId,
                durationSeconds: durationSeconds,
                transcribedText: transcribedText,
                signalAnalysis: signalAnalysis,
                speechMetrics: speechMetrics
            ),
            userId: userId
        )
    }

    private func transcriptionFallbackContext(
        noteId: UUID,
        durationSeconds: TimeInterval,
        transcribedText: String,
        signalAnalysis: AudioSignalAnalysis?,
        speechMetrics: TranscriptionSpeechMetrics?
    ) -> [String: String] {
        var context: [String: String] = [
            "note_id": noteId.uuidString,
            "duration_seconds": String(Int(durationSeconds)),
            "transcript_preview": String(transcribedText.prefix(80))
        ]

        context["speech_sample_ratio"] = signalAnalysis.map { String($0.speechSampleRatio) } ?? "n/a"
        context["rms_amplitude"] = signalAnalysis.map { String($0.rmsAmplitude) } ?? "n/a"
        context["speech_detected"] = speechMetrics?.speechDetected.map { String($0) } ?? "n/a"
        context["likely_speech_segment_ratio"] = speechMetrics?.likelySpeechSegmentRatio.map { String($0) } ?? "n/a"
        context["avg_no_speech_prob"] = speechMetrics?.avgNoSpeechProb.map { String($0) } ?? "n/a"
        context["avg_logprob"] = speechMetrics?.avgLogprob.map { String($0) } ?? "n/a"

        return context
    }

    private func transcriptionTimeoutSeconds(for durationSeconds: Int?) -> TimeInterval {
        switch durationSeconds ?? 0 {
        case 900...:
            return 420
        case 300...:
            return 300
        default:
            return 180
        }
    }

    private func performTranscriptionWithTimeout(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> TranscriptionResult
    ) async throws -> TranscriptionResult {
        try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TranscriptionWorkflowError.timedOut(seconds: seconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
