import Foundation

struct TranscriptionResult {
    let text: String
    let language: String?
    let audioUrl: String?
    let durationSeconds: Double?
}

final class TranscriptionService {
    func transcribe(audioData: Data, language: String?) async throws -> TranscriptionResult {
        // TODO: Call Supabase edge function → Groq Whisper
        fatalError("Not implemented")
    }
}
