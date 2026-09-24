import Foundation

public enum ChatGPTLaunchEnvironment {
    public static let port = 8_000
    public static let apiBaseURL = "https://localhost:8000/backend-api"

    public enum Error: Swift.Error, Equatable {
        case conflictingBackend
    }

    public static func connected(inheriting environment: [String: String]) throws -> [String: String] {
        var result = environment
        for key in ["CODEX_API_BASE_URL", "CODEX_APP_SERVER_CHATGPT_BASE_URL"] {
            let current = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let current, !current.isEmpty, current != apiBaseURL {
                throw Error.conflictingBackend
            }
            result[key] = apiBaseURL
        }
        return result
    }
}
