import AVFoundation
import Observation

@Observable
final class AudioPlayer {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVPlayer?
    private var currentURL: URL?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?

    func play(url: URL) {
        if let player, currentURL == url {
            // Resume existing player
            player.play()
            isPlaying = true
            return
        }

        // New file
        stop()
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

        newPlayer.play()
        self.player = newPlayer
        self.currentURL = url
        self.currentTime = 0
        self.isPlaying = true
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
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        player?.pause()
        player = nil
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
