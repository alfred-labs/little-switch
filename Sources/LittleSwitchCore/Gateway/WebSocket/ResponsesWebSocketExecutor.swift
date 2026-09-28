import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchWire
import NIOCore

package struct ResponsesWebSocketExecutor: Sendable {
    private typealias ResponseKey = OpenAIResponsesResponse.Key
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    let responder: GatewayResponder
    let request: Request
    let limits: ResponsesWebSocketLimits

    package func execute(
        _ turn: ResponsesWebSocketTurn,
        emit: @escaping @Sendable (Data) async throws -> Void
    ) async throws -> ResponsesWebSocketEventResult {
        if !turn.generate { return try await warmup(turn, emit: emit) }
        let response = try await responder.respond(to: httpRequest(body: turn.body))
        let projection = ResponsesWebSocketResponseProjection(
            status: response.status.code,
            streaming: response.headers[.contentType]?.lowercased().contains("text/event-stream") == true,
            streamID: turn.streamID,
            maximumBytes: limits.maxResponseBytes,
            emit: emit)
        try await response.body.write(ResponsesWebSocketResponseWriter(projection: projection))
        return try await projection.result()
    }

    package func httpRequest(body: Data) -> Request {
        var head = request.head
        head.method = .post
        let headers = request.headers.filter { field in
            let name = field.name.canonicalName
            return !name.hasPrefix("sec-websocket-")
                && !["connection", "upgrade", "content-length", "content-encoding", "transfer-encoding"].contains(name)
        }
        head.headerFields = HTTPFields(headers)
        head.headerFields[.contentType] = "application/json"
        head.headerFields[.accept] = "text/event-stream"
        return Request(head: head, body: .init(buffer: ByteBuffer(bytes: body)))
    }

    private func warmup(
        _ turn: ResponsesWebSocketTurn,
        emit: @escaping @Sendable (Data) async throws -> Void
    ) async throws -> ResponsesWebSocketEventResult {
        let source = try JSONValue.parse(turn.body)
        guard let model = source.object?[OpenAIResponsesRoutingRequest.Key.model.rawValue]?.string else {
            throw failure("invalid_request", "A model is required", turn: turn)
        }
        let capture = try await responder.dependencies.snapshotCapturer.capture(state: responder.state)
        try Task.checkCancellation()
        if let target = capture.snapshot.resolveCodex(model: model) {
            do {
                let degraded = try ResponsesProviderState.degradedBody(turn.body)
                _ = try PreparedGatewayResponses(
                    body: degraded, target: target, configuration: capture.snapshot.webSearch)
            } catch {
                throw ResponsesWebSocketFailure(
                    status: 400,
                    code: "invalid_request_error",
                    message: "Invalid Responses request",
                    streamID: turn.streamID,
                    parameter: "input")
            }
        } else if CodexNativePassthrough.isNativeRequest(turn.body) {
            let sentinel = "Bearer \(CodexNativePassthrough.sentinelAPIKey)"
            if request.headers[.authorization]?.caseInsensitiveCompare(sentinel) == .orderedSame {
                throw ResponsesWebSocketFailure(
                    status: 401,
                    code: "invalid_request_error",
                    message: CodexNativePassthrough.sentinelRejectionMessage,
                    streamID: turn.streamID)
            }
        } else {
            throw failure("model_not_found", "Unknown or invalid model", turn: turn)
        }
        let responseID = "resp_ls_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        var response: JSONObject = [
            ResponseKey.id.rawValue: .string(responseID),
            ResponseKey.object.rawValue: OpenAIResponsesResponseObject.response.wireJSON(),
            ResponseKey.createdAt.rawValue: .integer(Int(Date().timeIntervalSince1970)),
            OpenAIResponsesRoutingRequest.Key.model.rawValue: .string(model),
            ResponseKey.status.rawValue: OpenAIResponsesStatus.inProgress.wireJSON(),
            ResponseKey.output.rawValue: .array([]),
            ResponseKey.usage.rawValue: .null,
        ]
        var events = ResponsesWebSocketEvents(streamID: turn.streamID, maximumBytes: limits.maxResponseBytes)
        let openingEvents = [
            OpenAIResponsesCreatedEventType.responseCreated.rawValue,
            OpenAIResponsesInProgressEventType.responseInProgress.rawValue,
        ]
        for (sequence, type) in openingEvents.enumerated() {
            let event: JSONObject = [
                EventKey.type.rawValue: .string(type),
                ResponsesWebSocketContract.EventField.sequenceNumber.rawValue: .integer(sequence),
                EventKey.response.rawValue: .object(response),
            ]
            if let data = try events.accept(JSONValue.object(event).serializedData()) { try await emit(data) }
        }
        response[ResponseKey.status.rawValue] = OpenAIResponsesStatus.completed.wireJSON()
        _ = try events.accept(
            JSONValue.object([
                EventKey.type.rawValue: OpenAIResponsesCompletedEventType.responseCompleted.wireJSON(),
                ResponsesWebSocketContract.EventField.sequenceNumber.rawValue: .integer(2),
                EventKey.response.rawValue: .object(response),
            ])
            .serializedData())
        return try events.finish()
    }

    private func failure(_ code: String, _ message: String, turn: ResponsesWebSocketTurn) -> ResponsesWebSocketFailure {
        ResponsesWebSocketFailure(
            status: 400, code: code, message: message, streamID: turn.streamID, parameter: "model")
    }
}
