import Foundation

/// Guards the call identity carried alongside function-call argument events:
/// a provider may repeat `call_id` and `name` but may not change them
/// mid-call. Absent or null fields mean unchanged.
package func validateOptionalFunctionMetadata(
    _ payload: [String: Any],
    callID: String,
    name: String
) throws {
    // vLLM argument deltas repeat call_id and name as explicit nulls —
    // a null means unchanged, not a different id (`as? String` drops it).
    if let value = payload["call_id"] as? String, value != callID {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    if let value = payload["name"] as? String, value != name {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
}
