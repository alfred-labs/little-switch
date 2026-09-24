import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

extension ChatGPTGatewayResponder {
    func conversationResponse(
        _ request: ChatGPTConversationRequest,
        owner: String,
        history: ChatGPTHistoryStore,
        context: Context
    ) async throws -> Response {
        let id = request.conversationID ?? ChatGPTConversationID.make()
        let channel = ChatGPTStreamChannel()
        let ready = AsyncThrowingStream<ChatGPTPendingTurn, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let gateway = GatewayResponder(
            state: state,
            transport: transport,
            secretStore: secretStore,
            trafficRecorder: trafficRecorder,
            monitoring: monitoring
        )
        let task = try await activeTurns.start(key: .init(owner: owner, conversationID: id)) {
            do {
                try Task.checkCancellation()
                let pending = try await history.begin(
                    request: request,
                    owner: owner,
                    now: Date().timeIntervalSince1970,
                    newConversationID: request.conversationID == nil ? id : nil
                )
                ready.continuation.yield(pending)
                ready.continuation.finish()
                let projection = ChatGPTTurnProjection(
                    pending: pending,
                    model: request.model,
                    owner: owner,
                    history: history,
                    channel: channel
                )
                do {
                    try await channel.send(projection.initial())
                    let body = try request.responsesBody(history: pending.history)
                    // A new request crosses the provider boundary. Native cookies,
                    // account headers and bearer credentials are never inherited.
                    let providerRequest = Request(
                        head: HTTPRequest(
                            method: .post,
                            scheme: "http",
                            authority: "localhost:11436",
                            path: "/v1/responses",
                            headerFields: [.contentType: "application/json"]
                        ),
                        body: RequestBody(buffer: ByteBuffer(bytes: body))
                    )
                    let response = try await gateway.respond(to: providerRequest, context: context)
                    guard response.status == .ok else { throw ChatGPTConversationError.providerFailed }
                    try await response.body.write(ChatGPTProjectionWriter(projection: projection))
                    await channel.finish()
                } catch {
                    await projection.fail(cancelled: Task.isCancelled || error is CancellationError)
                }
            } catch {
                ready.continuation.finish(throwing: error)
                await channel.cancel()
            }
        }
        do {
            _ = try await withTaskCancellationHandler {
                var iterator = ready.stream.makeAsyncIterator()
                guard let pending = try await iterator.next() else { throw CancellationError() }
                return pending
            } onCancel: {
                task.cancel()
            }
        } catch {
            task.cancel()
            throw error
        }
        let lifetime = ChatGPTResponseLifetime(task: task)
        return Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-store"],
            body: ResponseBody { writer in
                _ = lifetime
                do {
                    while let data = try await channel.next() {
                        try await writer.write(ByteBuffer(bytes: data))
                    }
                    try await writer.finish(nil)
                } catch {
                    lifetime.task.cancel()
                    await channel.cancel()
                    throw error
                }
            }
        )
    }
}

/// The response owns the task, but the producer never owns this guard. Dropping
/// an unwritten response therefore cancels a producer waiting on backpressure.
private final class ChatGPTResponseLifetime: Sendable {
    let task: Task<Void, Never>
    init(task: Task<Void, Never>) { self.task = task }
    deinit { task.cancel() }
}

private struct ChatGPTProjectionWriter: ResponseBodyWriter, Sendable {
    let projection: ChatGPTTurnProjection
    mutating func write(_ buffer: ByteBuffer) async throws { try await projection.append(buffer) }
    consuming func finish(_ trailingHeaders: HTTPFields?) async throws { try await projection.finish() }
}
