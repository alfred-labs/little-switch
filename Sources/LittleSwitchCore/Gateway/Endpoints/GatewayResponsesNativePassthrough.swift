import AsyncHTTPClient
import Foundation
import Hummingbird
import LittleSwitchTransport
import NIOHTTP1

/// Codex's native upstreams for models outside the LittleSwitch catalog.
/// Native turns keep the user's own session and reusable native state.
package enum CodexNativePassthrough {
    package static let chatGPTBaseURL = "https://chatgpt.com/backend-api/codex"
    package static let openAIBaseURL = "https://api.openai.com/v1"
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
            !model.contains("/")
        else {
            return false
        }
        return true
    }

    static func isSentinelAuthorization(_ headers: HTTPHeaders) -> Bool {
        let value = headers["authorization"].first ?? ""
        return value.caseInsensitiveCompare("Bearer \(sentinelAPIKey)") == .orderedSame
    }

    static func upstreamURL(accountSession: Bool) -> String {
        accountSession ? chatGPTBaseURL + "/responses" : openAIBaseURL + "/responses"
    }

    static func forwardedHeaders(_ incoming: HTTPHeaders) -> HTTPHeaders {
        var forwarded = incoming
        let connectionTokens = forwarded["connection"].flatMap { value in
            value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        }
        for name in [
            "connection",
            "content-encoding",
            "content-length",
            "host",
            "keep-alive",
            "proxy-authenticate",
            "proxy-authorization",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
        ] + connectionTokens {
            forwarded.remove(name: name)
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
            return try await nativePassthroughResponsesResponse(
                body: nativeBody, incomingHeaders: incomingHeaders, eventID: eventID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badRequest, message: "Invalid Responses history")
        }
    }

    package func nativePassthroughResponsesResponse(
        body: Data,
        incomingHeaders: HTTPHeaders,
        eventID: UUID
    ) async throws -> Response {
        guard !CodexNativePassthrough.isSentinelAuthorization(incomingHeaders) else {
            return openAIError(
                status: .unauthorized,
                message: CodexNativePassthrough.sentinelRejectionMessage
            )
        }
        var upstreamRequest = HTTPClientRequest(
            url: CodexNativePassthrough.upstreamURL(
                accountSession: !incomingHeaders["chatgpt-account-id"].isEmpty
            )
        )
        upstreamRequest.method = .POST
        upstreamRequest.headers = CodexNativePassthrough.forwardedHeaders(incomingHeaders)
        upstreamRequest.body = .bytes(body)
        trafficRecorder.record(
            eventID: eventID,
            action: .annotation(
                TrafficAnnotation(
                    kind: "native-passthrough",
                    message: TrafficRedactor.url(upstreamRequest.url)
                )
            )
        )
        let upstream: HTTPClientResponse
        do {
            try Task.checkCancellation()
            upstream = try await transport.execute(upstreamRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return openAIError(status: .badGateway, message: "Provider request failed")
        }
        return streamingResponse(upstream, eventID: eventID, attempt: 0)
    }
}
