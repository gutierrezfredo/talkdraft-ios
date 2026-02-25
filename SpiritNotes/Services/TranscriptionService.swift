import Foundation
import os

private let logger = Logger(subsystem: "com.pleymob.spiritnotes", category: "Transcription")

struct TranscriptionResult: Sendable {
    let text: String
    let language: String?
    let audioUrl: String?
    let durationSeconds: Int?
}

final class TranscriptionService: Sendable {

    private let edgeFunctionURL = AppConfig.supabaseUrl
        .appendingPathComponent("functions/v1/transcribe")

    /// Locale-based prompt hints to bias Whisper's language detection
    private static let localePrompts: [String: String] = [
        "en": "This is a voice note.",
        "es": "Esta es una nota de voz.",
        "fr": "Ceci est une note vocale.",
        "pt": "Esta é uma nota de voz.",
        "de": "Dies ist eine Sprachnotiz.",
        "it": "Questa è una nota vocale.",
        "ja": "これは音声メモです。",
        "ko": "이것은 음성 메모입니다.",
        "zh": "这是一条语音备忘录。",
        "ar": "هذه ملاحظة صوتية.",
        "ru": "Это голосовая заметка.",
        "hi": "यह एक वॉइस नोट है।",
    ]

    func transcribe(audioData: Data, fileName: String, language: String?, userId: UUID?) async throws -> TranscriptionResult {
        let boundary = UUID().uuidString
        let ext = (fileName as NSString).pathExtension.lowercased()
        let mimeType = Self.mimeType(for: ext)
        let sizeMB = String(format: "%.1f", Double(audioData.count) / 1_048_576.0)

        logger.info("Transcribing \(fileName) (\(sizeMB)MB) via multipart upload")

        var body = Data()

        // File part
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendMultipart("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        body.appendMultipart("\r\n")

        // Language part
        if let language {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.appendMultipart("\(language)\r\n")
        }

        // Prompt hint — use device locale to bias language detection when auto
        let promptLang = language ?? Locale.current.language.languageCode?.identifier
        if let promptLang, let prompt = Self.localePrompts[promptLang] {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.appendMultipart("\(prompt)\r\n")
        }

        // User ID part (for storage upload on the server side)
        if let userId {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n")
            body.appendMultipart("\(userId.uuidString)\r\n")
        }

        body.appendMultipart("--\(boundary)--\r\n")

        logger.info("Request body size: \(String(format: "%.1f", Double(body.count) / 1_048_576.0))MB")

        var request = URLRequest(url: edgeFunctionURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 300 // 5 minutes — large files on slow connections

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Transcription failed: HTTP \(httpResponse.statusCode) — \(message)")
            throw TranscriptionError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        logger.info("Transcription succeeded")

        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return TranscriptionResult(
            text: result.text,
            language: result.language,
            audioUrl: result.audioUrl,
            durationSeconds: result.durationSeconds
        )
    }

    // MARK: - Helpers

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "m4a", "aac": "audio/m4a"
        case "ogg", "oga": "audio/ogg"
        case "flac": "audio/flac"
        case "webm": "audio/webm"
        case "mp4": "audio/mp4"
        case "caf": "audio/x-caf"
        default: "audio/\(ext)"
        }
    }
}

// MARK: - Response

private struct TranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let audioUrl: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from transcription service"
        case .serverError(let code, let message):
            "Transcription failed (\(code)): \(message)"
        }
    }
}

// MARK: - Data Helper

private extension Data {
    mutating func appendMultipart(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
