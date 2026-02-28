import Accelerate
import AVFoundation
import Observation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "AudioRecorder")

enum RecordingError: LocalizedError {
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .formatUnavailable:
            "Audio format unavailable"
        }
    }
}

@Observable
final class AudioRecorder {
    var isRecording = false
    var isPaused = false
    var elapsedSeconds: TimeInterval = 0
    var frequencyBands: [Float] = Array(repeating: 0, count: 20)
    private var pipeline: AudioPipeline?
    private var timer: Timer?
    private var startTime: Date?
    private var pausedElapsed: TimeInterval = 0
    private var interruptionObserver: Any?

    private let bandCount = 20

    deinit {
        timer?.invalidate()
        pipeline?.stop()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    private var recordingDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)

        let fileName = UUID().uuidString + ".m4a"
        let fileURL = recordingDirectory.appendingPathComponent(fileName)

        let pipeline = AudioPipeline(outputURL: fileURL, bandCount: bandCount)
        try pipeline.start()
        self.pipeline = pipeline

        isRecording = true
        isPaused = false
        startTime = Date()
        pausedElapsed = 0
        elapsedSeconds = 0
        frequencyBands = Array(repeating: 0, count: bandCount)

        observeInterruptions()
        startTimer()
    }

    func pauseRecording() {
        pipeline?.pause()
        isPaused = true
        pausedElapsed = elapsedSeconds
        timer?.invalidate()
        timer = nil
        frequencyBands = Array(repeating: 0, count: bandCount)
    }

    func resumeRecording() {
        // Restart engine if it was stopped by an interruption
        if let pipeline, !pipeline.isRunning {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try pipeline.restart()
            } catch {
                logger.error("Failed to restart audio engine: \(error)")
                return
            }
        }
        pipeline?.resume()
        isPaused = false
        startTime = Date()
        startTimer()
    }

    func stopRecording() -> URL? {
        removeInterruptionObserver()
        timer?.invalidate()
        timer = nil

        let url = pipeline?.fileURL
        pipeline?.stop()
        pipeline = nil

        // Deactivate audio session so it doesn't interfere with network requests
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        isPaused = false
        startTime = nil
        pausedElapsed = 0

        return url
    }

    func cancelRecording() {
        removeInterruptionObserver()
        timer?.invalidate()
        timer = nil

        let url = pipeline?.fileURL
        pipeline?.stop()
        pipeline = nil

        isRecording = false
        isPaused = false

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        startTime = nil
        pausedElapsed = 0
        elapsedSeconds = 0
        frequencyBands = Array(repeating: 0, count: bandCount)
    }

    // MARK: - Audio Interruption

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            switch type {
            case .began:
                if self.isRecording, !self.isPaused {
                    self.pauseRecording()
                    logger.info("Recording paused due to audio interruption")
                }
            case .ended:
                let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
                if options.contains(.shouldResume), self.isRecording, self.isPaused {
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        try self.pipeline?.restart()
                        self.resumeRecording()
                        logger.info("Recording resumed after interruption")
                    } catch {
                        logger.error("Failed to resume after interruption: \(error)")
                    }
                }
            @unknown default:
                break
            }
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }

            // Detect engine stopped unexpectedly (e.g. phone call with compact UI)
            if let pipeline = self.pipeline, !pipeline.isRunning, !self.isPaused {
                self.pauseRecording()
                logger.info("Recording paused — audio engine stopped unexpectedly")
                return
            }

            if let start = self.startTime {
                self.elapsedSeconds = self.pausedElapsed + Date().timeIntervalSince(start)
            }

            guard let pipeline = self.pipeline else { return }
            let latestBands = pipeline.readBands()
            for i in 0..<self.bandCount {
                let target = latestBands[i]
                let current = self.frequencyBands[i]
                if target > current {
                    self.frequencyBands[i] = current + (target - current) * 0.6
                } else {
                    self.frequencyBands[i] = current + (target - current) * 0.25
                }
            }

        }
    }
}

// MARK: - Audio Pipeline (single AVAudioEngine for recording + FFT)

private final class AudioPipeline: @unchecked Sendable {
    let fileURL: URL

    private let engineLock = NSLock()
    private var engine: AVAudioEngine?
    private let processor: FFTProcessor
    private let bridge: BandBridge
    private let paused = OSAllocatedUnfairLock(initialState: false)

    init(outputURL: URL, bandCount: Int) {
        self.fileURL = outputURL
        self.processor = FFTProcessor(fftSize: 1024, bandCount: bandCount)
        self.bridge = BandBridge(count: bandCount)
    }

    func start() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)

        // On simulator (no mic), channelCount is 0 — start engine without tap
        guard tapFormat.channelCount > 0 else {
            try engine.start()
            engineLock.lock()
            self.engine = engine
            engineLock.unlock()
            return
}

        // Target format: mono 16kHz — optimal for Whisper
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw RecordingError.formatUnavailable
        }

        guard let converter = AVAudioConverter(from: tapFormat, to: outputFormat) else {
            throw RecordingError.formatUnavailable
        }

        // Create M4A file: mono 16kHz AAC
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Capture only Sendable references — no self in closure
        let processor = self.processor
        let bridge = self.bridge
        let paused = self.paused

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            let isPaused = paused.withLock { $0 }
            guard !isPaused else { return }

            // Convert to mono 16kHz before writing
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let convertedFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: convertedFrameCount) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                try? file.write(from: convertedBuffer)
            }

            // FFT uses original buffer for visualization
            let bands = processor.process(buffer: buffer)
            bridge.write(bands)
        }

        try engine.start()
        engineLock.lock()
        self.engine = engine
        engineLock.unlock()
    }

    func pause() {
        paused.withLock { $0 = true }
    }

    func resume() {
        paused.withLock { $0 = false }
    }

    func stop() {
        engineLock.lock()
        let eng = engine
        engine = nil
        engineLock.unlock()
        eng?.inputNode.removeTap(onBus: 0)
        eng?.stop()
    }

    var isRunning: Bool {
        engineLock.lock()
        let running = engine?.isRunning ?? false
        engineLock.unlock()
        return running
    }

    func restart() throws {
        engineLock.lock()
        let eng = engine
        engineLock.unlock()
        guard let eng, !eng.isRunning else { return }
        try eng.start()
    }

    func readBands() -> [Float] {
        bridge.read()
    }
}

// MARK: - Thread-safe band storage

private final class BandBridge: Sendable {
    private let state: OSAllocatedUnfairLock<[Float]>

    init(count: Int) {
        state = OSAllocatedUnfairLock(initialState: Array(repeating: 0, count: count))
    }

    func write(_ bands: [Float]) {
        state.withLock { $0 = bands }
    }

    func read() -> [Float] {
        state.withLock { $0 }
    }
}

// MARK: - FFT Processor (pre-allocated buffers, called on audio thread)
// Symmetric bar visualization: compute half bars from center outward,
// apply edge blending + dampening, then mirror for symmetry.

private final class FFTProcessor: @unchecked Sendable {
    private let fftSize: Int
    private let halfSize: Int
    private let bandCount: Int
    private let halfBandCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    // Pre-allocated buffers — zero heap allocation per callback
    private var window: [Float]
    private var windowedData: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var dbMagnitudes: [Float]
    private var halfBars: [Float]
    private var bands: [Float]

    // Pre-computed bin ranges for the half-bar set
    private let bandRanges: [(start: Int, end: Int)]

    // dB-to-byte conversion constants (matches Web Audio getByteFrequencyData)
    private let dbMin: Float = -100
    private let dbRange: Float = 70       // -100 to -30
    private let noiseFloorByte: Float = 80
    private let byteRange: Float = 175    // 255 - 80

    private let skipBins = 5

    init(fftSize: Int, bandCount: Int) {
        self.fftSize = fftSize
        self.halfSize = fftSize / 2
        self.bandCount = bandCount
        self.halfBandCount = (bandCount + 1) / 2
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!

        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        windowedData = [Float](repeating: 0, count: fftSize)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        dbMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        halfBars = [Float](repeating: 0, count: (bandCount + 1) / 2)
        bands = [Float](repeating: 0, count: bandCount)

        // Map half-bars across usable bins (skip low rumble)
        let usableBins = fftSize / 2 - skipBins
        let half = (bandCount + 1) / 2
        var ranges = [(start: Int, end: Int)]()
        for i in 0..<half {
            let startFrac = pow(Float(i) / Float(half), 2.0)
            let endFrac = pow(Float(i + 1) / Float(half), 2.0)
            let start = skipBins + Int(startFrac * Float(usableBins))
            let end = max(start + 1, skipBins + Int(endFrac * Float(usableBins)))
            ranges.append((start, min(end, fftSize / 2 - 1)))
        }
        bandRanges = ranges
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func process(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else {
            return Array(repeating: 0, count: bandCount)
        }

        let frameCount = min(Int(buffer.frameLength), fftSize)

        // Apply Hann window via vectorized multiply
        vDSP_vmul(channelData, 1, window, 1, &windowedData, 1, vDSP_Length(frameCount))
        // Zero-fill remainder
        if frameCount < fftSize {
            var zero: Float = 0
            vDSP_vfill(&zero, &windowedData + frameCount, 1, vDSP_Length(fftSize - frameCount))
        }

        // Pack into split complex
        windowedData.withUnsafeBufferPointer { dataPtr in
            dataPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) {
                complexPtr in
                var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
                vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
            }
        }

        // Forward FFT
        var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // Squared magnitudes
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))

        // Convert to dB in bulk: 10*log10(mag) = 20*log10(sqrt(mag))
        // Normalize by FFT size squared to match Web Audio convention
        var fftNorm = Float(fftSize * fftSize)
        vDSP_vsdiv(magnitudes, 1, &fftNorm, &magnitudes, 1, vDSP_Length(halfSize))
        var halfSizeI = Int32(halfSize)
        // log10 of squared magnitudes, then multiply by 10 = same as 20*log10(magnitude)
        var floor: Float = 1e-20
        vDSP_vthr(magnitudes, 1, &floor, &magnitudes, 1, vDSP_Length(halfSize))
        vvlog10f(&dbMagnitudes, magnitudes, &halfSizeI)
        var ten: Float = 10
        vDSP_vsmul(dbMagnitudes, 1, &ten, &dbMagnitudes, 1, vDSP_Length(halfSize))

        // Step 1: Map dB magnitudes to half-bars with noise floor
        let half = halfBandCount
        for i in 0..<half {
            let range = bandRanges[i]
            var sum: Float = 0
            var count: Float = 0
            for bin in range.start...range.end {
                let byte = max(0, min(255, 255 * (dbMagnitudes[bin] - dbMin) / dbRange))
                let floored = byte > noiseFloorByte ? byte - noiseFloorByte : 0
                sum += floored
                count += 1
            }
            halfBars[i] = min(1, sum / count / byteRange)
        }

        // Step 2: Edge blending — pull outer bars toward average energy
        var totalEnergy: Float = 0
        for i in 0..<half { totalEnergy += halfBars[i] }
        let avgEnergy = totalEnergy / Float(half)

        for i in 0..<half {
            let edgeness = Float(i) / Float(half)
            let blendFactor = edgeness * 0.2
            halfBars[i] = halfBars[i] * (1 - blendFactor) + avgEnergy * blendFactor
        }

        // Step 3: Monotonic constraint + edge dampening
        for i in 1..<half {
            halfBars[i] = min(halfBars[i], halfBars[i - 1])
            let edgeDampen: Float = 1 - (Float(i) / Float(half)) * 0.5
            halfBars[i] *= edgeDampen
        }

        // Step 4: Mirror — center bars are loudest
        for i in 0..<half {
            bands[half - 1 - i] = halfBars[i]
            if half + i < bandCount {
                bands[half + i] = halfBars[i]
            }
        }

        return bands
    }
}
