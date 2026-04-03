import Accelerate
@preconcurrency import AVFoundation
import Observation
import os
import UIKit

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "AudioRecorder")

private struct PreparedRecordingSession: Sendable {
    let usesCarAudioRoute: Bool
}

enum RecordingError: LocalizedError {
    case formatUnavailable
    case incompatibleCarAudioRoute

    var errorDescription: String? {
        switch self {
        case .formatUnavailable:
            "Audio format unavailable"
        case .incompatibleCarAudioRoute:
            "Talkdraft couldn't start recording with the current car audio route. Try using the iPhone microphone or disconnecting CarPlay, then try again."
        }
    }
}

@Observable
final class AudioRecorder: @unchecked Sendable {
    var isRecording = false
    var isPaused = false
    var elapsedSeconds: TimeInterval = 0
    var frequencyBands: [Float] = Array(repeating: 0, count: 20)
    var didRecordInBackground = false
    private var pipeline: AudioPipeline?
    private var timer: Timer?
    private var startTime: Date?
    private var pausedElapsed: TimeInterval = 0
    private var interruptionObserver: Any?
    private var routeChangeObserver: Any?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var startedOnCarAudioRoute = false

    private let bandCount = 20

    @MainActor private static var sessionPreparationTask: Task<PreparedRecordingSession, Error>?

    deinit {
        timer?.invalidate()
        pipeline?.stop()
        endBackgroundTaskIfNeeded()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    private var recordingDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    @MainActor
    static func prewarmRecordingSession() {
        guard sessionPreparationTask == nil else { return }
        sessionPreparationTask = Task(priority: .userInitiated) { @MainActor in
            try Task.checkCancellation()
            let session = AVAudioSession.sharedInstance()
            let usesCarAudioRoute = Self.routeUsesCarAudio(session.currentRoute)
            guard !usesCarAudioRoute else {
                logger.info(
                    "Skipping recording session prewarm for car audio route. route=\(Self.describeRoute(session.currentRoute), privacy: .public)"
                )
                return PreparedRecordingSession(usesCarAudioRoute: usesCarAudioRoute)
            }
            try Self.refreshSessionForCurrentRoute(session)
            try Task.checkCancellation()
            logger.info(
                "Prewarmed recording session. route=\(Self.describeRoute(session.currentRoute), privacy: .public)"
            )
            return PreparedRecordingSession(usesCarAudioRoute: usesCarAudioRoute)
        }
    }

    static func currentRouteUsesCarAudio() -> Bool {
        routeUsesCarAudio(AVAudioSession.sharedInstance().currentRoute)
    }

    @MainActor
    static func discardPreparedRecordingSession() {
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredInput(nil)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    @MainActor
    private static func consumePreparedRecordingSession() async throws -> PreparedRecordingSession? {
        guard let task = sessionPreparationTask else { return nil }
        defer { sessionPreparationTask = nil }
        return try await task.value
    }

    @MainActor
    func startRecording() async throws {
        let startTimestamp = Date()
        let session = AVAudioSession.sharedInstance()
        do {
            let preparedSession = try await Self.consumePreparedRecordingSession()
            let usesCarAudioRoute = Self.routeUsesCarAudio(session.currentRoute)
            if preparedSession?.usesCarAudioRoute != usesCarAudioRoute {
                try Self.refreshSessionForCurrentRoute(session)
            }
            try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)

            let fileName = UUID().uuidString + ".m4a"
            let fileURL = recordingDirectory.appendingPathComponent(fileName)

            let pipeline = AudioPipeline(
                outputURL: fileURL,
                bandCount: bandCount,
                allowRecorderFallback: usesCarAudioRoute
            )
            try pipeline.start()
            self.pipeline = pipeline
            self.startedOnCarAudioRoute = usesCarAudioRoute

            isRecording = true
            isPaused = false
            startTime = Date()
            pausedElapsed = 0
            elapsedSeconds = 0
            frequencyBands = Array(repeating: 0, count: bandCount)

            observeInterruptions()
            observeRouteChanges()
            startTimer()
            beginBackgroundTaskIfNeeded()
            logger.info(
                "Recording started in \(Date().timeIntervalSince(startTimestamp), format: .fixed(precision: 3))s"
            )
        } catch {
            logger.error(
                "Failed to start recording. error=\(error.localizedDescription, privacy: .public) route=\(Self.describeRoute(session.currentRoute), privacy: .public) availableInputs=\(Self.describeInputs(session.availableInputs), privacy: .public)"
            )
            pipeline?.stop()
            pipeline = nil
            startedOnCarAudioRoute = false
            removeInterruptionObserver()
            removeRouteChangeObserver()
            try? session.setPreferredInput(nil)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)

            if Self.routeUsesCarAudio(session.currentRoute) {
                throw RecordingError.incompatibleCarAudioRoute
            }
            throw error
        }
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
                let session = AVAudioSession.sharedInstance()
                try Self.refreshSessionForCurrentRoute(session)
                try pipeline.restart()
            } catch {
                let session = AVAudioSession.sharedInstance()
                logger.error(
                    "Failed to restart audio engine. error=\(error.localizedDescription, privacy: .public) route=\(Self.describeRoute(session.currentRoute), privacy: .public)"
                )
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
        removeRouteChangeObserver()
        timer?.invalidate()
        timer = nil

        let url = pipeline?.fileURL
        pipeline?.stop()
        pipeline = nil

        // Deactivate audio session so it doesn't interfere with network requests
        try? AVAudioSession.sharedInstance().setPreferredInput(nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        isPaused = false
        didRecordInBackground = false
        startedOnCarAudioRoute = false
        startTime = nil
        pausedElapsed = 0
        endBackgroundTaskIfNeeded()

        return url
    }

    func cancelRecording() {
        removeInterruptionObserver()
        removeRouteChangeObserver()
        timer?.invalidate()
        timer = nil

        let url = pipeline?.fileURL
        pipeline?.stop()
        pipeline = nil
        try? AVAudioSession.sharedInstance().setPreferredInput(nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        isPaused = false
        didRecordInBackground = false
        startedOnCarAudioRoute = false

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        startTime = nil
        pausedElapsed = 0
        elapsedSeconds = 0
        frequencyBands = Array(repeating: 0, count: bandCount)
        endBackgroundTaskIfNeeded()
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

    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let session = AVAudioSession.sharedInstance()
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            logger.info(
                "Audio route changed. reason=\(String(describing: reason), privacy: .public) route=\(Self.describeRoute(session.currentRoute), privacy: .public)"
            )

            guard self.isRecording else { return }
            guard self.startedOnCarAudioRoute || Self.routeUsesCarAudio(session.currentRoute) else { return }
            do {
                try Self.refreshSessionForCurrentRoute(session)
                if let pipeline = self.pipeline, self.isPaused, !pipeline.isRunning {
                    try pipeline.restart()
                    self.pipeline?.resume()
                    self.isPaused = false
                    self.startTime = Date()
                    self.startTimer()
                    logger.info("Recording recovered after route change")
                }
            } catch {
                logger.error(
                    "Failed to refresh recording session after route change: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func removeRouteChangeObserver() {
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    // MARK: - Background

    func handleEnteredBackground() {
        guard isRecording, !isPaused else { return }
        didRecordInBackground = true
        beginBackgroundTaskIfNeeded()
        logger.info("Recording continues in background")
    }

    func handleReturnedToForeground() {
        endBackgroundTaskIfNeeded()
        if let pipeline, !pipeline.isRunning, !isPaused {
            pauseRecording()
            logger.info("Recording paused — engine stopped while in background")
        }
    }

    func clearBackgroundIndicator() {
        didRecordInBackground = false
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "AudioRecording") { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }

            // Detect engine stopped unexpectedly (e.g. phone call with compact UI)
            if let pipeline = self.pipeline, !pipeline.isRunning, !self.isPaused {
                if self.recoverStoppedEngineIfPossible() {
                    return
                }
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

    private static func refreshSessionForCurrentRoute(_ session: AVAudioSession) throws {
        let category = recordingCategory(for: session.currentRoute)
        let options = recordingCategoryOptions(for: session.currentRoute)
        try session.setCategory(category, mode: .default, options: options)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        try configurePreferredInputIfNeeded(session)
        logger.info(
            "Configured recording session. category=\(category.rawValue, privacy: .public) options=\(String(describing: options), privacy: .public) route=\(Self.describeRoute(session.currentRoute), privacy: .public)"
        )
    }

    private static func configurePreferredInputIfNeeded(_ session: AVAudioSession) throws {
        guard routeUsesCarAudio(session.currentRoute) else {
            try session.setPreferredInput(nil)
            return
        }

        // On wired CarPlay, forcing a preferred input can destabilize route negotiation.
        // Let iOS choose the active microphone, but keep logging the available inputs.
        logger.info(
            "Car audio route active; leaving preferred input unchanged. preferred=\(session.preferredInput?.portName ?? "nil", privacy: .public) availableInputs=\(Self.describeInputs(session.availableInputs), privacy: .public)"
        )
    }

    private static func recordingCategoryOptions(for route: AVAudioSessionRouteDescription) -> AVAudioSession.CategoryOptions {
        routeUsesCarAudio(route) ? [] : [.defaultToSpeaker]
    }

    private static func recordingCategory(for route: AVAudioSessionRouteDescription) -> AVAudioSession.Category {
        // Wired CarPlay only needs microphone capture here; using a record-only session
        // avoids forcing iOS to negotiate a simultaneous car-audio output route.
        routeUsesCarAudio(route) ? .record : .playAndRecord
    }

    private func recoverStoppedEngineIfPossible() -> Bool {
        guard let pipeline, startedOnCarAudioRoute || Self.routeUsesCarAudio(AVAudioSession.sharedInstance().currentRoute) else {
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try Self.refreshSessionForCurrentRoute(session)
            try pipeline.restart()
            logger.info("Recovered stopped audio engine on car audio route")
            return true
        } catch {
            let session = AVAudioSession.sharedInstance()
            logger.error(
                "Failed to recover stopped audio engine. error=\(error.localizedDescription, privacy: .public) route=\(Self.describeRoute(session.currentRoute), privacy: .public)"
            )
            return false
        }
    }

    private static func routeUsesCarAudio(_ route: AVAudioSessionRouteDescription) -> Bool {
        route.outputs.contains { $0.portType == .carAudio } || route.inputs.contains { $0.portType == .carAudio }
    }

    private static func describeRoute(_ route: AVAudioSessionRouteDescription) -> String {
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        return "inputs=[\(inputs)] outputs=[\(outputs)]"
    }

    private static func describeInputs(_ inputs: [AVAudioSessionPortDescription]?) -> String {
        (inputs ?? []).map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
    }
}

// MARK: - Audio Pipeline (single AVAudioEngine for recording + FFT)

private final class AudioPipeline: @unchecked Sendable {
    let fileURL: URL

    private let engineLock = NSLock()
    private var engine: AVAudioEngine?
    private var recorder: AVAudioRecorder?
    private let processor: FFTProcessor
    private let bridge: BandBridge
    private let paused = OSAllocatedUnfairLock(initialState: false)
    private let bandCount: Int
    private let allowRecorderFallback: Bool

    init(outputURL: URL, bandCount: Int, allowRecorderFallback: Bool) {
        self.fileURL = outputURL
        self.bandCount = bandCount
        self.allowRecorderFallback = allowRecorderFallback
        self.processor = FFTProcessor(fftSize: 1024, bandCount: bandCount)
        self.bridge = BandBridge(count: bandCount)
    }

    func start() throws {
        do {
            try startEngineBackend()
        } catch {
            guard allowRecorderFallback else {
                throw error
            }
            logger.error("AVAudioEngine start failed, falling back to AVAudioRecorder. error=\(error.localizedDescription, privacy: .public)")
            try startRecorderBackend()
        }
    }

    private func startEngineBackend() throws {
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

        // Record at full quality for playback — downsampling happens at upload time
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: min(tapFormat.channelCount, 2),
            AVEncoderBitRateKey: 128_000,
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

        inputNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
            let isPaused = paused.withLock { $0 }
            guard !isPaused else { return }

            try? file.write(from: buffer)

            // FFT uses original buffer for visualization
            let bands = processor.process(buffer: buffer)
            bridge.write(bands)
        }

        engine.prepare()
        try engine.start()
        engineLock.lock()
        self.engine = engine
        engineLock.unlock()
    }

    private func startRecorderBackend() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else {
            throw RecordingError.formatUnavailable
        }
        guard recorder.record() else {
            throw RecordingError.formatUnavailable
        }

        self.recorder = recorder
    }

    func pause() {
        paused.withLock { $0 = true }
        recorder?.pause()
    }

    func resume() {
        paused.withLock { $0 = false }
        if let recorder, !recorder.isRecording {
            recorder.record()
        }
    }

    func stop() {
        engineLock.lock()
        let eng = engine
        engine = nil
        engineLock.unlock()
        eng?.inputNode.removeTap(onBus: 0)
        eng?.stop()
        recorder?.stop()
        recorder = nil
    }

    var isRunning: Bool {
        engineLock.lock()
        let running = engine?.isRunning ?? false
        engineLock.unlock()
        return running || (recorder?.isRecording ?? false)
    }

    func restart() throws {
        if let recorder {
            if !recorder.isRecording && !recorder.record() {
                throw RecordingError.formatUnavailable
            }
            return
        }

        engineLock.lock()
        let eng = engine
        engineLock.unlock()
        guard let eng, !eng.isRunning else { return }
        try eng.start()
    }

    func readBands() -> [Float] {
        if let recorder {
            recorder.updateMeters()
            let averagePower = recorder.averagePower(forChannel: 0)
            let normalizedLevel = max(0, min(1, (averagePower + 60) / 60))
            let bands = Array(repeating: normalizedLevel, count: bandCount)
            bridge.write(bands)
            return bands
        }

        return bridge.read()
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

    private func withSplitComplex<Result>(
        _ body: (inout DSPSplitComplex) -> Result
    ) -> Result {
        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imagBuffer.baseAddress!
                )
                return body(&split)
            }
        }
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
            windowedData.withUnsafeMutableBufferPointer { buffer in
                var zero: Float = 0
                vDSP_vfill(
                    &zero,
                    buffer.baseAddress!.advanced(by: frameCount),
                    1,
                    vDSP_Length(fftSize - frameCount)
                )
            }
        }

        // Pack into split complex
        windowedData.withUnsafeBufferPointer { dataPtr in
            dataPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) {
                complexPtr in
                withSplitComplex { split in
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                }
            }
        }

        // Forward FFT
        withSplitComplex { split in
            vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
        }

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
