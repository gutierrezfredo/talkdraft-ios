@preconcurrency import AVFoundation
import Observation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "AudioPlayer")

@Observable
final class AudioPlayer: @unchecked Sendable {
    var isPlaying = false
    var isBuffering = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVPlayer?
    private var currentURL: URL?
    private var currentItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var bufferingObservation: NSKeyValueObservation?

    /// Call when the audio UI becomes visible to start buffering ahead of playback.
    func preload(url: URL) {
        guard currentURL != url else { return }
        stop()
        prepare(url: url)
    }

    func play(url: URL) {
        if let player, currentURL == url {
            // Resume or start already-prepared player
            activateAudioSession()
            player.play()
            isPlaying = true
            return
        }

        stop()
        prepare(url: url)
        activateAudioSession()
        player?.play()
        isPlaying = true
    }

    private func prepare(url: URL) {
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)

        // Observe duration once the asset loads
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay else { return }
            let seconds = item.duration.seconds
            if seconds.isFinite {
                self.duration = seconds
            }
        }

        // Observe rate changes for play/pause state
        rateObservation = newPlayer.observe(\.rate) { [weak self] player, _ in
            guard let self else { return }
            self.isPlaying = player.rate > 0
        }

        // Observe buffering state
        bufferingObservation = newPlayer.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self else { return }
            self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        }

        // Periodic time updates
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                self.currentTime = seconds
            }
        }

        // Observe playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        self.player = newPlayer
        self.currentItem = item
        self.currentURL = url
        self.currentTime = 0
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback(url: URL) {
        if isPlaying {
            pause()
        } else {
            play(url: url)
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                      toleranceBefore: .zero,
                      toleranceAfter: .zero)
        currentTime = clamped
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
        bufferingObservation?.invalidate()
        bufferingObservation = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        player?.pause()
        player = nil
        currentItem = nil
        currentURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    @objc private func playerDidFinish(_ notification: Notification) {
        isPlaying = false
        currentTime = 0
        player?.seek(to: .zero)
    }
}
