import Accelerate
import AVFoundation
import Observation
import os

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

    private let bandCount = 20

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
        pipeline?.resume()
        isPaused = false
        startTime = Date()
        startTimer()
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        let url = pipeline?.fileURL
        pipeline?.stop()
        pipeline = nil

        isRecording = false
        isPaused = false
        startTime = nil
        pausedElapsed = 0

        return url
    }

    func cancelRecording() {
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

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }

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

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
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
            self.engine = engine
            return
        }

        // Create M4A file matching the tap's native PCM format
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: tapFormat.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: fileSettings,
            commonFormat: tapFormat.commonFormat,
            interleaved: tapFormat.isInterleaved
        )
        self.audioFile = file

        // Capture only Sendable references — no self in closure
        let processor = self.processor
        let bridge = self.bridge
        let paused = self.paused

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            let isPaused = paused.withLock { $0 }
            guard !isPaused else { return }

            try? file.write(from: buffer)
            let bands = processor.process(buffer: buffer)
            bridge.write(bands)
        }

        try engine.start()
        self.engine = engine
    }

    func pause() {
        paused.withLock { $0 = true }
    }

    func resume() {
        paused.withLock { $0 = false }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
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

private final class FFTProcessor: @unchecked Sendable {
    private let fftSize: Int
    private let halfSize: Int
    private let bandCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    // Pre-allocated buffers — reused every callback, zero heap allocation per call
    private var window: [Float]
    private var windowedData: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var sqrtMagnitudes: [Float]
    private var bands: [Float]

    // Pre-computed band bin ranges
    private let bandRanges: [(start: Int, end: Int)]

    init(fftSize: Int, bandCount: Int) {
        self.fftSize = fftSize
        self.halfSize = fftSize / 2
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!

        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        windowedData = [Float](repeating: 0, count: fftSize)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        sqrtMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        bands = [Float](repeating: 0, count: bandCount)

        var ranges = [(start: Int, end: Int)]()
        let half = fftSize / 2
        for band in 0..<bandCount {
            let startRatio = pow(Float(band) / Float(bandCount), 2.0)
            let nextRatio = pow(Float(band + 1) / Float(bandCount), 2.0)
            let startBin = max(1, Int(startRatio * Float(half)))
            let endBin = max(startBin, min(half - 1, Int(nextRatio * Float(half))))
            ranges.append((startBin, endBin))
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
        if frameCount < fftSize {
            for i in frameCount..<fftSize {
                windowedData[i] = 0
            }
        }

        // Pack into split complex format
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

        // Compute magnitudes
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
        var halfSizeLen = Int32(halfSize)
        vvsqrtf(&sqrtMagnitudes, magnitudes, &halfSizeLen)

        // Map to logarithmic frequency bands, normalize to 0–1
        for band in 0..<bandCount {
            let range = bandRanges[band]
            var sum: Float = 0
            for bin in range.start...range.end {
                sum += sqrtMagnitudes[bin]
            }
            let avg = sum / Float(range.end - range.start + 1)
            let db = 20 * log10(max(avg, 1e-10))
            bands[band] = max(0, min(1, (db + 50) / 40))
        }

        return bands
    }
}
