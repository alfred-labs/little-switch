import Foundation

/// Adapted requests reconstruct history from input and cannot resolve provider-owned state.
package enum ResponsesConversationReferences {
    static func hasServerState(in request: [String: Any]) -> Bool {
        ["previous_response_id", "conversation"].contains { key in
            guard let value = request[key] else { return false }
            return !(value is NSNull)
        }
    }
}
