import Foundation

enum AIService {

    /// Ephemeral session avoids stale connection reuse (fixes -1005 on SSE streams).
    private static let streamingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    static func generateTitle(for content: String, language: String? = nil) async throws -> String {
        let url = AppConfig.supabaseUrl.appendingPathComponent("functions/v1/generate-title")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["text": content]
        if let language { body["language"] = language }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.serverError(errorText)
        }

        let result = try JSONDecoder().decode(TitleResponse.self, from: data)
        guard let title = result.title, !title.isEmpty else {
            throw AIError.emptyResult
        }
        return title
    }

    static func rewrite(content: String, tone: String?, customInstructions: String?, language: String?) async throws -> String {
        let url = AppConfig.supabaseUrl.appendingPathComponent("functions/v1/rewrite")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        var body: [String: Any] = ["text": content]
        if let tone { body["tone"] = tone }
        if let customInstructions, !customInstructions.isEmpty { body["customInstructions"] = customInstructions }
        if let language { body["language"] = language }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.serverError(errorText)
        }

        let result = try JSONDecoder().decode(RewriteResponse.self, from: data)
        return result.rewritten
    }

    static func rewriteStreaming(
        content: String,
        tone: String?,
        customInstructions: String?,
        language: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await performStreaming(
                        content: content,
                        tone: tone,
                        customInstructions: customInstructions,
                        language: language,
                        continuation: continuation
                    )
                } catch let error as URLError where error.code == .networkConnectionLost {
                    // Retry once on -1005 (stale connection)
                    do {
                        try await performStreaming(
                            content: content,
                            tone: tone,
                            customInstructions: customInstructions,
                            language: language,
                            continuation: continuation
                        )
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func performStreaming(
        content: String,
        tone: String?,
        customInstructions: String?,
        language: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let url = AppConfig.supabaseUrl.appendingPathComponent("functions/v1/rewrite")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        var body: [String: Any] = ["text": content]
        if let tone { body["tone"] = tone }
        if let customInstructions, !customInstructions.isEmpty { body["customInstructions"] = customInstructions }
        if let language { body["language"] = language }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await streamingSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIError.serverError("Server returned non-200 status")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data)
            else { continue }

            continuation.yield(chunk.text)
        }

        continuation.finish()
    }

    static func translate(content: String, targetLanguage: String) async throws -> String {
        throw AIError.notImplemented
    }
}

// MARK: - Response Types

private struct TitleResponse: Decodable {
    let title: String?
}

private struct RewriteResponse: Decodable {
    let rewritten: String
}

private struct StreamChunk: Decodable {
    let text: String
}

// MARK: - Errors

enum AIError: LocalizedError {
    case serverError(String)
    case emptyResult
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .serverError(let message): "AI request failed: \(message)"
        case .emptyResult: "AI returned an empty result"
        case .notImplemented: "This feature is not yet available"
        }
    }
}
