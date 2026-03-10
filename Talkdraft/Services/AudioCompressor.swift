import AVFoundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "AudioCompressor")

/// Compresses audio to 16kHz mono AAC — the format Whisper processes internally.
/// Reduces upload size by 5-10x. Applies a high-pass filter (100 Hz cutoff) during
/// compression to remove low-frequency handling noise and pocket rumble, improving
/// transcription accuracy without affecting the original stored recording.
enum AudioCompressor {

    static func compress(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CompressionError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        // Reader: decode to 16kHz mono Float32 PCM (Float32 required for in-place DSP)
        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        // Writer: encode to AAC at 32kbps
        // shouldOptimizeForNetworkUse moves the moov atom to the front of the file,
        // required for streaming decoders (Deepgram) to decode the full file.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        writer.shouldOptimizeForNetworkUse = true
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

        let queue = DispatchQueue(label: "com.pleymob.talkdraft.audiocompress")
        let hpf = HPFState()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard reader.status == .reading,
                          let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    // Apply high-pass filter in-place before encoding
                    hpf.process(buffer)
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

// MARK: - High-Pass Filter

/// First-order IIR high-pass filter, ~100 Hz cutoff at 16 kHz.
/// Removes low-frequency rumble from handling noise and pocket recording.
/// α = RC / (RC + dt)  where RC = 1/(2π × 100 Hz), dt = 1/16000
private final class HPFState: @unchecked Sendable {
    private var prevX: Float = 0
    private var prevY: Float = 0
    private let alpha: Float = 0.9624

    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        var dataPtr: UnsafeMutablePointer<CChar>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                    lengthAtOffsetOut: nil,
                                    totalLengthOut: nil,
                                    dataPointerOut: &dataPtr)
        guard let ptr = dataPtr else { return }
        let floats = UnsafeMutableRawPointer(ptr).bindMemory(to: Float.self, capacity: byteCount / 4)
        let count = byteCount / 4
        for i in 0 ..< count {
            let x = floats[i]
            let y = alpha * (prevY + x - prevX)
            prevX = x
            prevY = y
            floats[i] = y
        }
    }
}
