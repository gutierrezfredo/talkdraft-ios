import AVFoundation
import Observation

@Observable
final class AudioRecorder {
    var isRecording = false
    var isPaused = false
    var durationMs: Int = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?

    func startRecording() throws {
        // TODO: Configure AVAudioSession, start AVAudioRecorder
    }

    func pauseRecording() {
        // TODO: Pause recording
    }

    func resumeRecording() {
        // TODO: Resume recording
    }

    func stopRecording() -> URL? {
        // TODO: Stop recording, return file URL
        return nil
    }
}
