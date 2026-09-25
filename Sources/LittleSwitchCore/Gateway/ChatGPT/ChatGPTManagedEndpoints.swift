import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

extension ChatGPTGatewayResponder {
    func managedResponse(
        _ route: ChatGPTManagedRoute, request: Request, context: Context, capture: GatewayRoutingCapture
    ) async throws -> Response? {
        if case .native = route { return nil }
        let owner = try ChatGPTRequestBoundary.accountPartition(headers: request.headers)
        guard let history else { throw ChatGPTActiveTurns.Failure.stopped }
        switch route {
        case .native: return nil
        // swift-format keeps bindings inside enum payloads.
        // swiftlint:disable:next pattern_matching_keywords
        case .prepare(let model, let id, let initialize):
            let stored: ChatGPTStoredConversation?
            if let id { stored = try await history.conversation(id: id, owner: owner) } else { stored = nil }
            var metadata: [String: String] = [:]
            if initialize {
                metadata[ChatGPTNativeContract.EventField.type.rawValue] =
                    ChatGPTNativeContract.EventType.conversationDetailMetadata.rawValue
                metadata[ChatGPTNativeContract.ConversationField.defaultModelSlug.rawValue] =
                    model ?? stored.flatMap { $0.nodes[$0.currentNodeID]?.model }
                metadata[ChatGPTNativeContract.EventField.conversationId.rawValue] = id
            }
            return jsonResponse(try JSONEncoder().encode(metadata))
        case .generate(let decoded):
            return try await conversationResponse(
                decoded, owner: owner, history: history, context: context, capture: capture)
        case .detail(let id):
            return try await jsonResponse(history.conversation(id: id, owner: owner).nativeData())
        case .status(let id):
            let stored = try await history.conversation(id: id, owner: owner)
            let status = stored.nodes[stored.currentNodeID]?.status
            let native =
                status == .inProgress
                ? ChatGPTNativeContract.StreamStatus.streaming.rawValue
                : status == .finishedSuccessfully
                    ? ChatGPTNativeContract.StreamStatus.complete.rawValue
                    : ChatGPTNativeContract.StreamStatus.failure.rawValue
            return jsonResponse(
                try JSONEncoder().encode([
                    ChatGPTNativeContract.EventField.status.rawValue: native,
                    ChatGPTNativeContract.EventField.conversationId.rawValue: id,
                ]))
        case .stop(let id):
            _ = try await history.conversation(id: id, owner: owner)
            await activeTurns.cancel(key: .init(owner: owner, conversationID: id))
            return jsonResponse(Data(#"{"success":true}"#.utf8))
        // swift-format keeps bindings inside enum payloads.
        // swiftlint:disable:next pattern_matching_keywords
        case .patch(let id, let changes):
            try await history.patch(id: id, owner: owner, changes: changes, now: Date().timeIntervalSince1970)
            return jsonResponse(Data(#"{"success":true}"#.utf8))
        case .remove(let id):
            try await history.remove(id: id, owner: owner)
            return jsonResponse(Data(#"{"success":true}"#.utf8))
        }
    }

    func jsonResponse(_ data: Data) -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    func managedErrorResponse(_ error: any Error) throws -> Response {
        switch error {
        case ChatGPTRequestBoundary.Error.missingSession:
            try errorResponse(.unauthorized, "A ChatGPT session is required")
        case ChatGPTHistoryError.notFound:
            try errorResponse(.notFound, "The local model or conversation is unavailable")
        case ChatGPTHistoryError.busy, ChatGPTActiveTurns.Failure.busy:
            try errorResponse(.conflict, "This conversation already has an active response")
        case ChatGPTHistoryError.capacityExceeded, ChatGPTConversationError.limitExceeded:
            try errorResponse(.contentTooLarge, "The local conversation limit has been reached")
        case ChatGPTActiveTurns.Failure.capacity:
            try errorResponse(.tooManyRequests, "Too many local conversations are active")
        case ChatGPTActiveTurns.Failure.stopped:
            try errorResponse(.serviceUnavailable, "The local ChatGPT connection is unavailable")
        case ChatGPTConversationError.invalidRequest, ChatGPTConversationError.unsupportedRequest,
            ChatGPTHistoryError.invalidInput:
            try errorResponse(
                .badRequest,
                "Use a new text conversation with a LittleSwitch model; this action is unsupported"
            )
        default:
            try errorResponse(.internalServerError, "The local conversation could not be saved")
        }
    }
}
