import Foundation
import Hummingbird
import LittleSwitchSearch
import NIOCore

extension GatewayResponder {
    /// Answers Claude Desktop's built-in `websearch` server when the
    /// deployment profile points it here through `provider: "custom"`:
    /// one POST carrying `{q}` maps to one provider search, reusing the
    /// bridge's client, credential, and traffic recording, and comes back
    /// as the flat `results[]` array the server's own schema documents.
    package func managedWebSearchResponse(
        _ request: Request,
        eventID: UUID
    ) async throws -> Response {
        try Task.checkCancellation()
        let body: Data
        switch try await collect(request.body, errorStyle: .anthropic) {
        case .data(let value):
            body = value
        case .response(let response):
            return response
        }
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            let query = object["q"] as? String,
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return anthropicError(status: .badRequest, message: "Invalid web search request")
        }
        try Task.checkCancellation()
        let capture = try await dependencies.snapshotCapturer.capture(state: state)
        try Task.checkCancellation()
        let configuration = capture.snapshot.webSearch
        guard configuration.provider != .disabled else {
            return anthropicError(status: .serviceUnavailable, message: "Web search is disabled")
        }
        let credential = try webSearchCredential(for: configuration)
        let attempt = try await executeWebSearch(
            query: query,
            configuration: configuration,
            credential: credential,
            options: WebSearchFilterOptions(),
            eventID: eventID
        )
        guard let results = attempt.results else {
            // A missing key is actionable by the user, not a provider
            // outage: name it as such instead of the generic bad gateway.
            if let providerError = attempt.failure as? WebSearchProviderError, providerError == .missingCredential {
                return anthropicError(
                    status: .serviceUnavailable,
                    message: "Web search credential is missing"
                )
            }
            return anthropicError(status: .badGateway, message: "Web search provider failed")
        }
        let payload: [String: Any] = [
            "results": results.map { result in
                [
                    "title": result.title,
                    "url": result.url,
                    "snippet": result.content,
                ] as [String: Any]
            }
        ]
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(
                byteBuffer: ByteBuffer(bytes: safeGatewayJSONData(payload))
            )
        )
    }
}
