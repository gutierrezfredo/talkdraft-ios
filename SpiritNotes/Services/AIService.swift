import Foundation

enum AIService {

    static func generateTitle(for content: String) async throws -> String {
        // TODO: Call Supabase edge function → Gemini Flash
        fatalError("Not implemented")
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
            throw RewriteError.serverError(errorText)
        }

        let result = try JSONDecoder().decode(RewriteResponse.self, from: data)
        return result.rewritten
    }

    static func translate(content: String, targetLanguage: String) async throws -> String {
        // TODO: Call Supabase edge function → Gemini Flash
        fatalError("Not implemented")
    }
}

// MARK: - Rewrite Types

enum RewriteError: LocalizedError {
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let message): "Rewrite failed: \(message)"
        }
    }
}

private struct RewriteResponse: Decodable {
    let rewritten: String
}
