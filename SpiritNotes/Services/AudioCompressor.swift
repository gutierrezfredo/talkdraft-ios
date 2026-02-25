import AVFoundation
import os

private let logger = Logger(subsystem: "com.pleymob.spiritnotes", category: "AudioCompressor")

/// Compresses audio to 16kHz mono AAC — the format Whisper processes internally.
/// Reduces upload size by 5-10x with zero transcription quality loss.
enum AudioCompressor {

    static func compress(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CompressionError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        // Reader: decode to 16kHz mono PCM
        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        // Writer: encode to AAC at 32kbps
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writer.add(writerInput)

        // Process
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.pleymob.spiritnotes.audiocompress")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard reader.status == .reading,
                          let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    writerInput.append(buffer)
                }
            }
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw CompressionError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }

        // Log compression ratio
        if let originalSize = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int,
           let compressedSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int {
            let ratio = String(format: "%.1fx", Double(originalSize) / Double(compressedSize))
            let origMB = String(format: "%.1f", Double(originalSize) / 1_048_576.0)
            let compMB = String(format: "%.1f", Double(compressedSize) / 1_048_576.0)
            logger.info("Compressed \(origMB)MB → \(compMB)MB (\(ratio) reduction)")
        }

        return outputURL
    }

    /// Cleans up a temporary compressed file.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    enum CompressionError: LocalizedError {
        case noAudioTrack
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                "No audio track found in file"
            case .writeFailed(let reason):
                "Audio compression failed: \(reason)"
            }
        }
    }
}
