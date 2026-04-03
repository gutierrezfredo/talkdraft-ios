import Foundation

enum AIService {

    static func generateTitle(for content: String, language: String? = nil) async throws -> String {
        let url = AppConfig.supabaseUrl.appendingPathComponent("functions/v1/generate-title")
        let accessToken = try await supabase.auth.session.accessToken
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["text": content]
        if let language { body["language"] = language }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.serverError(statusCode: httpResponse.statusCode, message: errorText)
        }

        let result = try JSONDecoder().decode(TitleResponse.self, from: data)
        guard let title = result.title, !title.isEmpty else {
            throw AIError.emptyResult
        }
        return title
    }

    static func translate(content: String, targetLanguage: String) async throws -> String {
        throw AIError.notImplemented
    }
}

// MARK: - Response Types

private struct TitleResponse: Decodable {
    let title: String?
}

// MARK: - Errors

enum AIError: LocalizedError {
    case serverError(statusCode: Int, message: String)
    case emptyResult
    case invalidResponse
    case notImplemented

    var isTransient: Bool {
        switch self {
        case .serverError(let statusCode, _):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .emptyResult, .invalidResponse, .notImplemented:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .serverError(let statusCode, let message): "AI request failed (\(statusCode)): \(message)"
        case .emptyResult: "AI returned an empty result"
        case .invalidResponse: "AI returned an invalid response"
        case .notImplemented: "This feature is not yet available"
        }
    }
}
