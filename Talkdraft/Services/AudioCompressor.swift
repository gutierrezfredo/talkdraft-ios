@preconcurrency import AVFoundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "AudioCompressor")

/// Compresses audio to 16kHz mono AAC — the format Whisper processes internally.
/// Reduces upload size by 5-10x. Applies a high-pass filter (100 Hz cutoff) during
/// compression to remove low-frequency handling noise and pocket rumble, improving
/// transcription accuracy without affecting the original stored recording.
enum AudioCompressor {

    private final class ProcessingState: @unchecked Sendable {
        let reader: AVAssetReader
        let readerOutput: AVAssetReaderTrackOutput
        let writerInput: AVAssetWriterInput
        let hpf: HPFState

        init(
            reader: AVAssetReader,
            readerOutput: AVAssetReaderTrackOutput,
            writerInput: AVAssetWriterInput,
            hpf: HPFState
        ) {
            self.reader = reader
            self.readerOutput = readerOutput
            self.writerInput = writerInput
            self.hpf = hpf
        }
    }

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
        let state = ProcessingState(
            reader: reader,
            readerOutput: readerOutput,
            writerInput: writerInput,
            hpf: hpf
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.writerInput.requestMediaDataWhenReady(on: queue) {
                while state.writerInput.isReadyForMoreMediaData {
                    guard state.reader.status == .reading,
                          let buffer = state.readerOutput.copyNextSampleBuffer() else {
                        state.writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    // Apply high-pass filter in-place before encoding
                    state.hpf.process(buffer)
                    state.writerInput.append(buffer)
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

struct AudioSignalAnalysis: Sendable {
    let durationSeconds: TimeInterval
    let rmsAmplitude: Float
    let peakAmplitude: Float
    let speechSampleRatio: Float
}

enum AudioSignalAnalyzer {
    static func analyze(url: URL) async throws -> AudioSignalAnalysis {
        let asset = AVURLAsset(url: url)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioCompressor.CompressionError.noAudioTrack
        }

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)

        reader.startReading()

        var sumSquares: Double = 0
        var sampleCount: Int64 = 0
        var peak: Float = 0
        var speechLikeSampleCount: Int64 = 0

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            let byteCount = CMBlockBufferGetDataLength(blockBuffer)
            var dataPointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: nil,
                dataPointerOut: &dataPointer
            )
            guard let dataPointer else { continue }

            let floatCount = byteCount / MemoryLayout<Float>.size
            let samples = UnsafeMutableRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)

            for index in 0..<floatCount {
                let sample = samples[index]
                let magnitude = abs(sample)
                peak = max(peak, magnitude)
                sumSquares += Double(sample * sample)
                if magnitude >= 0.015 {
                    speechLikeSampleCount += 1
                }
            }
            sampleCount += Int64(floatCount)
        }

        if reader.status == .failed {
            throw reader.error ?? AudioCompressor.CompressionError.writeFailed("failed to analyze audio levels")
        }

        let rms = sampleCount > 0 ? sqrt(sumSquares / Double(sampleCount)) : 0
        let speechSampleRatio = sampleCount > 0
            ? Float(speechLikeSampleCount) / Float(sampleCount)
            : 0
        return AudioSignalAnalysis(
            durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
            rmsAmplitude: Float(rms),
            peakAmplitude: peak,
            speechSampleRatio: speechSampleRatio
        )
    }

    static func shouldTreatAsSilent(_ analysis: AudioSignalAnalysis) -> Bool {
        if analysis.peakAmplitude < 0.003 && analysis.rmsAmplitude < 0.0008 {
            return true
        }

        if analysis.durationSeconds <= 3 &&
            analysis.peakAmplitude < 0.02 &&
            analysis.rmsAmplitude < 0.004 {
            return true
        }

        if analysis.durationSeconds >= 4 &&
            analysis.rmsAmplitude < 0.01 &&
            analysis.speechSampleRatio < 0.015 &&
            analysis.peakAmplitude < 0.08 {
            return true
        }

        return false
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
