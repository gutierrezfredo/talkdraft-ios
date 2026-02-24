import AVFoundation
import Observation

@Observable
final class AudioPlayer {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVAudioPlayer?

    func play(url: URL) throws {
        // TODO: Initialize and play audio
    }

    func pause() {
        // TODO: Pause playback
    }

    func seek(to time: TimeInterval) {
        // TODO: Seek to position
    }

    func stop() {
        // TODO: Stop playback
    }
}
