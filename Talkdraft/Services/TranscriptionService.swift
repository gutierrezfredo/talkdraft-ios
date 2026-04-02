import Foundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "Transcription")

struct TranscriptionResult: Sendable {
    let text: String
    let language: String?
    let audioUrl: String?
    let durationSeconds: Int?
}

final class TranscriptionService: Sendable {

    private let edgeFunctionURL = AppConfig.supabaseUrl
        .appendingPathComponent("functions/v1/transcribe")

    private let diarizedFunctionURL = AppConfig.supabaseUrl
        .appendingPathComponent("functions/v1/transcribe-diarized")

    /// Soft language hints to improve recognition without forcing the model to
    /// emit text in the user's preferred language when the spoken audio differs.
    private static let preferredLanguageNames: [String: String] = [
        "ar": "Arabic",
        "de": "German",
        "en": "English",
        "es": "Spanish",
        "fr": "French",
        "hi": "Hindi",
        "it": "Italian",
        "ja": "Japanese",
        "ko": "Korean",
        "pt": "Portuguese",
        "ru": "Russian",
        "zh": "Chinese",
    ]

    func transcribe(audioData: Data, fileName: String, language: String?, userId: UUID?, customDictionary: [String] = [], whisperData: Data? = nil, whisperFileName: String? = nil, multiSpeaker: Bool = false) async throws -> TranscriptionResult {
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

        // Whisper file part (compressed version for transcription, if different from storage file)
        if let whisperData, let whisperFileName {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"whisper_file\"; filename=\"\(whisperFileName)\"\r\n")
            body.appendMultipart("Content-Type: audio/m4a\r\n\r\n")
            body.append(whisperData)
            body.appendMultipart("\r\n")
        }

        // Prompt — preferred language is treated as a recognition hint only.
        if let prompt = Self.transcriptionPrompt(preferredLanguage: language, customDictionary: customDictionary) {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.appendMultipart("\(prompt)\r\n")
        }

        // Transitional compatibility: older deployed edge functions still read
        // user_id for storage paths. Newer deployments derive ownership from the
        // caller JWT and ignore this field.
        if let userId {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n")
            body.appendMultipart("\(userId.uuidString)\r\n")
        }

        body.appendMultipart("--\(boundary)--\r\n")

        logger.info("Request body size: \(String(format: "%.1f", Double(body.count) / 1_048_576.0))MB")

        let targetURL = multiSpeaker ? diarizedFunctionURL : edgeFunctionURL
        let accessToken = try await supabase.auth.session.accessToken
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300 // 5 minutes — large files on slow connections

        // Write body to a temp file so iOS can stream it rather than buffer the
        // entire payload in memory — more resilient on slow/cellular connections.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")
        try body.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: tempURL)

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

    static func transcriptionPrompt(preferredLanguage: String?, customDictionary: [String]) -> String? {
        let dictionaryHint = customDictionary.isEmpty
            ? nil
            : "Prefer these spellings if they are spoken: \(customDictionary.joined(separator: ", "))."

        let languageHint = preferredLanguage
            .flatMap { preferredLanguageNames[$0] ?? Locale.current.localizedString(forLanguageCode: $0) }
            .map { "The speaker usually records in \($0). Use that only as a recognition hint." }

        let promptParts = [
            languageHint,
            "Transcribe the spoken words verbatim in the language actually spoken. Do not translate.",
            dictionaryHint,
        ].compactMap { $0 }

        guard !promptParts.isEmpty else { return nil }
        return promptParts.joined(separator: " ")
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
