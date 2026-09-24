import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import NIOHTTP1

/// Codex's native upstreams for models outside the LittleSwitch catalog.
/// Native turns keep the user's own session and reusable native state.
package enum CodexNativePassthrough {
    /// Only explicitly supported native operations can choose an upstream path.
    package enum Endpoint: String, Sendable {
        case responses
        case imageGenerations = "images/generations"
        case imageEdits = "images/edits"
    }

    package static let chatGPTBaseURL = "https://chatgpt.com/backend-api/codex"
    package static let openAIBaseURL = "https://api.openai.com/v1"
    static let accountIDHeader = "chatgpt-account-id"
    /// A local-only sentinel, never a real OpenAI credential. It exists so
    /// Codex can run without a signed-in session and is rejected before any
    /// native forwarding.
    package static let sentinelAPIKey = "little-switch-local-codex"
    package static let sentinelRejectionMessage =
        "OpenAI models require signing in to ChatGPT or adding an OpenAI API key"

    /// Whether the request carries a Responses model slug at all. Bodies
    /// without one keep the existing unknown-model rejection. LittleSwitch
    /// reserved slugs never pass through natively: an unresolved custom reviewer
    /// is a configuration error. Codex's own `codex-auto-review` stays native.
    static func isNativeRequest(_ body: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let model = root["model"] as? String,
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            model != CodexCatalog.managedAutoReviewModel,
            !model.contains("/"),
            !ManagedModelIdentifier.usesCanonicalNamespace(model)
        else {
            return false
        }
        return true
    }

    static func isSentinelAuthorization(_ headers: HTTPHeaders) -> Bool {
        let value = headers["authorization"].first ?? ""
        return value.caseInsensitiveCompare("Bearer \(sentinelAPIKey)") == .orderedSame
    }

    static func upstreamURL(accountSession: Bool, endpoint: Endpoint) -> String {
        let baseURL = accountSession ? chatGPTBaseURL : openAIBaseURL
        return baseURL + "/" + endpoint.rawValue
    }

    static func forwardedHeaders(_ incoming: HTTPHeaders, endpoint: Endpoint) -> HTTPHeaders {
        var forwarded = HTTPForwardingHeaders.endToEnd(incoming)
        // Responses bodies have been decoded and normalized. Image bodies
        // stay opaque, so their encoding must continue to describe the bytes.
        if endpoint == .responses {
            forwarded.remove(name: "content-encoding")
        }
        return forwarded
    }
}

extension GatewayResponder {
    package func nativeResponsesResponse(
        body: Data, incomingHeaders: HTTPHeaders, eventID: UUID
    ) async throws -> Response {
        do {
            // Native compaction is an upstream protocol operation. Preserve
            // its trigger, reasoning settings and opaque checkpoints just as
            // on ordinary native turns; only portable provider state expands.
            let nativeBody = try ResponsesChatCompletionsReasoning.nativeRequestBody(
                ResponsesProviderState.normalize(body: body, providerID: nil)
            )
            guard nativeBody.count <= maximumRequestBytes else {
                return openAIError(status: .contentTooLarge, message: "Expanded history is too large")
            }
            return try await nativePassthroughResponse(
                body: nativeBody, incomingHeaders: incomingHeaders, endpoint: .responses, eventID: eventID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badRequest, message: "Invalid Responses history")
        }
    }

}
