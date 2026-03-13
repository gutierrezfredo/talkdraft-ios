import AVFoundation
import Foundation

extension NoteStore {
    func retryWaitingNotes(language: String?, userId: UUID?) {
        let waiting = notes.filter {
            $0.content == "Waiting for connection…" || $0.content == "Transcription failed — tap to edit"
        }
        guard !waiting.isEmpty else { return }

        for note in waiting {
            guard let urlString = note.audioUrl,
                  let url = if let fileURL = URL(string: urlString), fileURL.isFileURL {
                      fileURL
                  } else if urlString.hasPrefix("/") {
                      URL(fileURLWithPath: urlString)
                  } else {
                      nil
                  },
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }

            setNoteContent(id: note.id, content: "Transcribing…")
            transcribeNote(id: note.id, audioFileURL: url, language: language, userId: userId)
        }
    }

    func importAudioNote(
        from sourceURL: URL,
        userId: UUID?,
        categoryId: UUID?,
        language: String?,
        requiresSecurityScopedAccess: Bool = true
    ) async throws -> Note {
        let destinationURL: URL
        if requiresSecurityScopedAccess {
            guard sourceURL.startAccessingSecurityScopedResource() else {
                throw ImportedAudioNoteError.accessDenied
            }
            do {
                defer { sourceURL.stopAccessingSecurityScopedResource() }
                destinationURL = try Self.copyImportedAudio(from: sourceURL)
            } catch {
                throw ImportedAudioNoteError.copyFailed
            }
        } else {
            do {
                destinationURL = try Self.copyImportedAudio(from: sourceURL)
            } catch {
                throw ImportedAudioNoteError.copyFailed
            }
        }

        let noteId = UUID()
        let note = Note(
            id: noteId,
            userId: userId,
            categoryId: categoryId,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            content: "Transcribing…",
            source: .voice,
            audioUrl: destinationURL.absoluteString,
            durationSeconds: await Self.importedAudioDurationSeconds(for: destinationURL),
            createdAt: .now,
            updatedAt: .now
        )

        addNote(note)
        transcribeNote(id: noteId, audioFileURL: destinationURL, language: language, userId: userId)
        return note
    }

    static func importedAudioDurationSeconds(for url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? Int(seconds) : nil
        } catch {
            return nil
        }
    }

    static func copyImportedAudio(from sourceURL: URL) throws -> URL {
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileName = if sourceURL.pathExtension.isEmpty {
            UUID().uuidString
        } else {
            "\(UUID().uuidString).\(sourceURL.pathExtension)"
        }
        let destinationURL = recordingsDir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func transcribeNote(id: UUID, audioFileURL: URL, language: String?, userId: UUID?) {
        Task {
            var compressedURL: URL?
            defer {
                if let compressedURL {
                    AudioCompressor.cleanup(compressedURL)
                }
            }

            do {
                guard FileManager.default.fileExists(atPath: audioFileURL.path),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path),
                      let fileSize = attrs[.size] as? Int,
                      fileSize > 0
                else {
                    noteStoreLogger.error("transcribeNote: audio file missing or empty at \(audioFileURL.path)")
                    setNoteContent(id: id, content: "Transcription failed — tap to edit")
                    return
                }

                do {
                    try await transcriptionConnectivityProbe()
                } catch {
                    noteStoreLogger.info("Connectivity probe failed — device appears offline: \(error)")
                    setNoteContent(id: id, content: "Waiting for connection…")
                    return
                }

                let uploadURL: URL
                do {
                    let compressed = try await AudioCompressor.compress(sourceURL: audioFileURL)
                    compressedURL = compressed
                    uploadURL = compressed
                } catch {
                    noteStoreLogger.warning("Compression failed, using original: \(error)")
                    uploadURL = audioFileURL
                }

                let audioData = try Data(contentsOf: uploadURL)
                let fileName = uploadURL.lastPathComponent

                let result = try await transcriptionUploadExecutor(
                    TranscriptionUploadRequest(
                        audioData: audioData,
                        fileName: fileName,
                        language: language,
                        userId: userId
                    )
                )

                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcribedText.isEmpty else {
                    noteStoreLogger.warning("transcribeNote: received empty transcription for \(id)")
                    setNoteContent(id: id, content: "Transcription failed — tap to edit")
                    return
                }

                guard var note = notes.first(where: { $0.id == id }) else {
                    noteStoreLogger.error("transcribeNote: note \(id) not found in local store after transcription")
                    return
                }
                note.content = transcribedText
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
                    try? FileManager.default.removeItem(at: audioFileURL)
                }

                generateTitle(for: id, content: transcribedText, language: result.language)
            } catch {
                noteStoreLogger.error("transcribeNote failed for \(id): \(error)")
                guard let noteIndex = notes.firstIndex(where: { $0.id == id }) else {
                    noteStoreLogger.error("transcribeNote: note \(id) not found in local store after failure")
                    return
                }

                if error is URLError {
                    notes[noteIndex].content = "Waiting for connection…"
                    notes[noteIndex].updatedAt = Date()
                } else {
                    notes[noteIndex].content = "Transcription failed — tap to edit"
                    notes[noteIndex].updatedAt = Date()
                }
            }
        }
    }

    func generateTitle(for noteId: UUID, content: String, language: String?) {
        Task {
            do {
                let aiTitle = try await aiTitleExecutor(content, language)
                guard var note = notes.first(where: { $0.id == noteId }) else { return }
                note.title = aiTitle
                note.updatedAt = Date()
                updateNote(note)
            } catch {
                // AI title failed — keep the quick title, no big deal
            }
        }
    }
}
