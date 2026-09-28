import AsyncAlgorithms
import Foundation
import Hummingbird

/// A single coordinator owns scheduling/cache and serializes socket writes.
/// Reader and model turns rendezvous with it, so there is no unbounded event inbox.
package struct ResponsesWebSocketSession: Sendable {
    private let executor: ResponsesWebSocketExecutor
    private let limits: ResponsesWebSocketLimits
    private let lifetime: Duration

    package init(
        responder: GatewayResponder,
        request: Request,
        limits: ResponsesWebSocketLimits = .init(),
        lifetime: Duration? = nil
    ) {
        executor = ResponsesWebSocketExecutor(responder: responder, request: request, limits: limits)
        self.limits = limits
        self.lifetime = lifetime ?? .seconds(limits.connectionLifetimeSeconds)
    }

    package func run<Messages: AsyncSequence & Sendable>(
        messages: Messages, send: @escaping @Sendable (Data) async throws -> Void
    ) async throws where Messages.Element == Data {
        let channel = AsyncChannel<Event>()
        let sink = Sink(channel: channel)
        var state = ResponsesWebSocketState(limits: limits)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await message in messages {
                        try Task.checkCancellation()
                        await channel.send(.received(message))
                    }
                } catch {
                    await channel.send(.readFailed(error))
                    return
                }
                await channel.send(.closed)
            }
            group.addTask {
                do {
                    try await Task.sleep(for: lifetime)
                    await channel.send(.expired)
                } catch {}
            }
            do {
                loop: for await event in channel {
                    try Task.checkCancellation()
                    switch event {
                    case .received(let frame):
                        do { try state.enqueue(frame) } catch let failure as ResponsesWebSocketFailure {
                            try await send(failure.encoded())
                        }
                    // swift-format keeps each associated-value binding local.
                    // swiftlint:disable:next pattern_matching_keywords
                    case .outbound(let data, let acknowledgement):
                        do {
                            try await send(data)
                            acknowledgement.finish()
                        } catch {
                            acknowledgement.finish(throwing: error)
                            throw error
                        }
                    // swiftlint:disable:next pattern_matching_keywords
                    case .finished(let turn, let result):
                        _ = try await group.next()
                        try await send(finish(turn, result: result, state: &state))
                    case .readFailed(let error):
                        throw error
                    case .expired:
                        try await send(
                            ResponsesWebSocketFailure(
                                status: 400,
                                code: "websocket_connection_limit_reached",
                                message: "Reconnect and replay context to continue"
                            ).encoded())
                        break loop
                    case .closed:
                        break loop
                    }
                    while let ready = state.next() {
                        switch ready {
                        case .failure(let failure):
                            try await send(failure.encoded())
                        case .success(let turn):
                            group.addTask {
                                let result: Result<ResponsesWebSocketEventResult, any Error>
                                do {
                                    result = .success(try await executor.execute(turn, emit: sink.send))
                                } catch {
                                    result = .failure(error)
                                }
                                await channel.send(.finished(turn, result))
                            }
                        }
                    }
                }
                channel.finish()
                group.cancelAll()
            } catch {
                channel.finish()
                group.cancelAll()
                throw error
            }
        }
    }

    private func finish(
        _ turn: ResponsesWebSocketTurn,
        result: Result<ResponsesWebSocketEventResult, any Error>,
        state: inout ResponsesWebSocketState
    ) throws -> Data {
        do {
            let completed = try result.get()
            let context = completed.responseID.flatMap { identifier in
                completed.output.map { ResponsesWebSocketCompletion(responseID: identifier, output: $0) }
            }
            try state.finish(turn, completion: context)
            return completed.terminal
        } catch {
            try state.finish(turn, completion: nil)
            let failure =
                (error as? ResponsesWebSocketFailure)
                ?? ResponsesWebSocketFailure(
                    status: 502,
                    code: "upstream_error",
                    message: "Provider response failed",
                    streamID: turn.streamID)
            return try failure.encoded()
        }
    }

    private enum Event: Sendable {
        case received(Data)
        case outbound(Data, AsyncThrowingStream<Void, any Error>.Continuation)
        case finished(ResponsesWebSocketTurn, Result<ResponsesWebSocketEventResult, any Error>)
        case readFailed(any Error)
        case closed
        case expired
    }

    private struct Sink: Sendable {
        let channel: AsyncChannel<Event>

        func send(_ data: Data) async throws {
            let (acknowledgements, continuation) = AsyncThrowingStream<Void, any Error>.makeStream(
                bufferingPolicy: .bufferingOldest(1))
            await channel.send(.outbound(data, continuation))
            for try await _ in acknowledgements {}
            try Task.checkCancellation()
        }
    }
}
