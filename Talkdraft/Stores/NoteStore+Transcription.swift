import Foundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "NoteStore")

extension NoteStore {
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
                    setNoteBodyState(id: id, state: .transcriptionFailed)
                    ErrorLogger.shared.log(
                        type: "transcription_empty",
                        message: "Whisper returned empty text",
                        context: ["note_id": id.uuidString, "language": language ?? "auto"],
                        userId: userId
                    )
                    return
                }

                // Update note with transcription
                guard var note = notes.first(where: { $0.id == id }) else {
                    logger.error("transcribeNote: note \(id) not found in local store after transcription")
                    return
                }
                let (formattedContent, initialSpeakerNames) = Self.formatMultiSpeakerTranscript(transcribedText)
                setLocalVoiceBodyState(nil, for: id)
                note.content = formattedContent
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
                generateTitle(for: id, content: transcribedText, language: result.language)
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
