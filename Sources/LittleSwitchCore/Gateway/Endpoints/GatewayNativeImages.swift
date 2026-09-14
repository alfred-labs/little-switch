import Foundation
import Hummingbird

extension GatewayResponder {
    /// Codex sends image edits as JSON; API clients may send multipart data.
    /// Preserve both formats without model routing or Responses normalization.
    package func nativeImagesResponse(
        _ request: Request, endpoint: CodexNativePassthrough.Endpoint, eventID: UUID
    ) async throws -> Response {
        let body: Data
        switch try await collect(request.body, errorStyle: .openAI) {
        case .data(let value):
            body = value
        case .response(let response):
            return response
        }
        trafficRecorder.record(eventID: eventID, action: .claudeRequestBody(body))
        return try await nativePassthroughResponse(
            body: body, incomingHeaders: nioHeaders(request.headers), endpoint: endpoint, eventID: eventID)
    }
}
