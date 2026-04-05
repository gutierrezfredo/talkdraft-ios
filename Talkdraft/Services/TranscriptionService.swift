import Foundation
import os

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "Transcription")

struct TranscriptionResult: Sendable {
    let text: String
    let language: String?
    let audioUrl: String?
    let durationSeconds: Int?
    let speechMetrics: TranscriptionSpeechMetrics?
}

struct TranscriptionSpeechMetrics: Decodable, Sendable {
    let speechDetected: Bool?
    let segmentCount: Int?
    let nonemptySegmentCount: Int?
    let likelySpeechSegmentRatio: Double?
    let avgNoSpeechProb: Double?
    let avgLogprob: Double?
    let avgCompressionRatio: Double?

    enum CodingKeys: String, CodingKey {
        case speechDetected = "speech_detected"
        case segmentCount = "segment_count"
        case nonemptySegmentCount = "nonempty_segment_count"
        case likelySpeechSegmentRatio = "likely_speech_segment_ratio"
        case avgNoSpeechProb = "avg_no_speech_prob"
        case avgLogprob = "avg_logprob"
        case avgCompressionRatio = "avg_compression_ratio"
    }
}

final class TranscriptionService: Sendable {
    static let noSpeechFallbackMessages = [
        "No speech detected. Try recording again.",
        "We couldn't pick up any words. Give it another go.",
        "This recording was too quiet to transcribe.",
        "Nothing to transcribe — the audio was mostly silence.",
        "No words were captured. Try speaking closer to the mic."
    ]
    private static let noSpeechFallbackRotationKey = "transcription.noSpeechFallbackRotationIndex"

    private let edgeFunctionURL = AppConfig.supabaseUrl
        .appendingPathComponent("functions/v1/transcribe")

    private let diarizedFunctionURL = AppConfig.supabaseUrl
        .appendingPathComponent("functions/v1/transcribe-diarized")

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

        // Some providers can echo instructional prompts back as transcript text,
        // so only send bare dictionary spellings here.
        if let prompt = Self.transcriptionPrompt(customDictionary: customDictionary) {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.appendMultipart("\(prompt)\r\n")
        }

        // Preferred language is sent separately for future backend heuristics,
        // but never as a hard transcription override.
        if let language {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"preferred_language\"\r\n\r\n")
            body.appendMultipart("\(language)\r\n")
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
        let sanitizedText = Self.sanitizedTranscriptText(result.text)
        return TranscriptionResult(
            text: sanitizedText,
            language: result.language,
            audioUrl: result.audioUrl,
            durationSeconds: result.durationSeconds,
            speechMetrics: result.speechMetrics
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

    static func transcriptionPrompt(customDictionary: [String]) -> String? {
        guard !customDictionary.isEmpty else { return nil }
        return customDictionary.joined(separator: ", ")
    }

    static func sanitizedTranscriptText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let pattern = #"([.!?…]["')\]]?)\s+you\.?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            regex.firstMatch(in: trimmed, range: range) != nil
        else {
            return trimmed
        }

        let sanitized = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "$1")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldUseShortRecordingFallback(
        for text: String,
        durationSeconds: TimeInterval?
    ) -> Bool {
        guard let durationSeconds, durationSeconds <= 3 else { return false }

        let normalized = normalizedTranscriptTokens(text)
        guard !normalized.tokens.isEmpty else { return false }

        let obviousHallucinationPhrases: Set<String> = [
            "thank you for watching",
            "thanks for watching",
            "thank you for listening",
            "please subscribe",
            "subscribe to my channel",
            "thanks for listening",
        ]

        if obviousHallucinationPhrases.contains(normalized.joined) {
            return true
        }

        if normalized.tokens.count >= 3, Set(normalized.tokens).count == 1 {
            return true
        }

        return false
    }

    static func shouldUseLowSpeechFallback(
        for text: String,
        analysis: AudioSignalAnalysis?,
        speechMetrics: TranscriptionSpeechMetrics?,
        usesCarAudioRoute: Bool = AudioRecorder.currentRouteUsesCarAudio()
    ) -> Bool {
        let normalized = normalizedTranscriptTokens(text)
        guard !normalized.tokens.isEmpty else { return false }

        let suspiciousGenericPhrases: Set<String> = [
            "thank you",
            "thanks",
            "thank you very much",
            "you",
        ]
        let genericNoiseTokens: Set<String> = [
            "a", "an", "and", "bye", "for", "hello", "hi", "hmm", "i", "im", "it's",
            "its", "no", "oh", "ok", "okay", "thanks", "thank", "the", "to", "uh",
            "um", "you", "yeah", "yep"
        ]

        let looksLikeMostlyNoise = analysis.map {
            $0.durationSeconds >= 2.5
                && $0.speechSampleRatio < (usesCarAudioRoute ? 0.015 : 0.05)
                && $0.rmsAmplitude < (usesCarAudioRoute ? 0.015 : 0.04)
                && $0.peakAmplitude < (usesCarAudioRoute ? 0.12 : 0.3)
        } ?? false

        let looksTrulySilentOnCarAudio = analysis.map {
            $0.durationSeconds >= 2.5
                && $0.speechSampleRatio < 0.008
                && $0.rmsAmplitude < 0.006
                && $0.peakAmplitude < 0.05
        } ?? false

        let backendSuggestsNoSpeech = speechMetrics.map { metrics in
            if metrics.speechDetected == false { return true }

            let likelySpeechSegmentRatio = metrics.likelySpeechSegmentRatio ?? 1
            let avgNoSpeechProb = metrics.avgNoSpeechProb ?? 0
            let avgLogprob = metrics.avgLogprob ?? 0
            let avgCompressionRatio = metrics.avgCompressionRatio ?? 0

            let highNoSpeechProbability = avgNoSpeechProb > 0.55
            let weakSpeechSegmentRatio = likelySpeechSegmentRatio < 0.4
            let lowConfidence = avgLogprob < -0.6
            let suspiciousCompression = avgCompressionRatio > 2.4

            return (highNoSpeechProbability && weakSpeechSegmentRatio)
                || (highNoSpeechProbability && lowConfidence)
                || (weakSpeechSegmentRatio && lowConfidence && suspiciousCompression)
        } ?? false

        let shouldTrustBackendOverLevels = usesCarAudioRoute
        let shouldEvaluateTranscriptAsNoSpeech =
            backendSuggestsNoSpeech
            || (!shouldTrustBackendOverLevels && looksLikeMostlyNoise)
            || (shouldTrustBackendOverLevels && looksTrulySilentOnCarAudio)

        guard shouldEvaluateTranscriptAsNoSpeech else { return false }
        if suspiciousGenericPhrases.contains(normalized.joined) {
            return true
        }

        let allTokensAreGenericNoise = normalized.tokens.allSatisfy { genericNoiseTokens.contains($0) }
        if allTokensAreGenericNoise && normalized.tokens.count <= 4 {
            return true
        }

        if backendSuggestsNoSpeech && normalized.tokens.count <= 3 && normalized.joined.count <= 16 {
            return true
        }

        return false
    }

    private static func normalizedTranscriptTokens(_ text: String) -> (tokens: [String], joined: String) {
        let scalars = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
            }
        let normalized = String(scalars)
        let tokens = normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return (tokens, tokens.joined(separator: " "))
    }

    static func noSpeechFallbackMessage(at rotationIndex: Int) -> String {
        let index = ((rotationIndex % noSpeechFallbackMessages.count) + noSpeechFallbackMessages.count) % noSpeechFallbackMessages.count
        return noSpeechFallbackMessages[index]
    }

    static func isNoSpeechFallbackText(_ text: String) -> Bool {
        noSpeechFallbackMessages.contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func nextNoSpeechFallbackText(defaults: UserDefaults = .standard) -> String {
        let currentIndex = defaults.integer(forKey: noSpeechFallbackRotationKey)
        let message = noSpeechFallbackMessage(at: currentIndex)
        defaults.set(currentIndex + 1, forKey: noSpeechFallbackRotationKey)
        return message
    }
}

// MARK: - Response

private struct TranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let audioUrl: String?
    let durationSeconds: Int?
    let speechMetrics: TranscriptionSpeechMetrics?

    enum CodingKeys: String, CodingKey {
        case text
        case language
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case speechMetrics = "speech_metrics"
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
