import Foundation

enum AIService {

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

    static func translate(content: String, targetLanguage: String) async throws -> String {
        // TODO: Call Supabase edge function → Gemini Flash
        fatalError("Not implemented")
    }
}

// MARK: - Response Types

private struct TitleResponse: Decodable {
    let title: String?
}

private struct RewriteResponse: Decodable {
    let rewritten: String
}

// MARK: - Errors

enum AIError: LocalizedError {
    case serverError(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .serverError(let message): "AI request failed: \(message)"
        case .emptyResult: "AI returned an empty result"
        }
    }
}
