import AsyncAlgorithms
import Foundation
import Hummingbird
import LittleSwitchTransport
import LittleSwitchWire

/// A single coordinator owns scheduling/cache and serializes socket writes.
/// Reader and model turns rendezvous with it, so there is no unbounded event inbox.
package struct ResponsesWebSocketSession: Sendable {
    private let executor: ResponsesWebSocketExecutor
    private let limits: ResponsesWebSocketLimits
    private let lifetime: Duration
    private let upstreamTransport: (any UpstreamWebSocketTransport)?
    private let clock: ResponsesUpstreamClock

    package init<C: Clock>(
        responder: GatewayResponder,
        request: Request,
        limits: ResponsesWebSocketLimits = .init(),
        lifetime: Duration? = nil,
        upstreamTransport: (any UpstreamWebSocketTransport)? = nil,
        clock: C = ContinuousClock()
    ) where C.Duration == Duration {
        executor = ResponsesWebSocketExecutor(responder: responder, request: request, limits: limits)
        self.limits = limits
        self.lifetime = lifetime ?? .seconds(limits.connectionLifetimeSeconds)
        self.upstreamTransport = upstreamTransport
        self.clock = ResponsesUpstreamClock(clock)
    }

    package func run<Messages: AsyncSequence & Sendable>(
        messages: Messages, send: @escaping @Sendable (Data) async throws -> Void
    ) async throws where Messages.Element == Data {
        let channel = AsyncChannel<Event>()
        let sink = Sink(channel: channel)
        let upstream = upstreamTransport.map {
            ResponsesUpstreamSession(transport: $0, limits: limits, clock: clock, control: sink.send)
        }
        var selectedExecutor = executor
        selectedExecutor.upstream = upstream
        let executor = selectedExecutor
        var state = ResponsesWebSocketState(limits: limits)
        let (steeringMessages, steeringInput) = AsyncStream<ResponsesWebSocketSteering>.makeStream(
            bufferingPolicy: .bufferingOldest(limits.maxQueuedRequests))
        var steeringQueue = ResponsesWebSocketSteeringQueue(input: steeringInput, limits: limits)
        try await withThrowingTaskGroup(of: Void.self) { group in
            if let upstream {
                group.addTask { await upstream.run() }
                group.addTask {
                    await forwardSteering(steeringMessages, upstream: upstream, channel: channel)
                }
            }
            group.addTask { await read(messages, channel: channel) }
            group.addTask { await expire(channel: channel) }
            do {
                loop: for await event in channel {
                    try Task.checkCancellation()
                    switch event {
                    case .received(let frame):
                        do {
                            try enqueue(frame, state: &state, steeringQueue: &steeringQueue)
                        } catch let failure as ResponsesWebSocketFailure {
                            try await send(failure.encoded())
                        }
                    // swift-format keeps each associated-value binding local.
                    // swiftlint:disable:next pattern_matching_keywords
                    case .outbound(let data, let acknowledgement):
                        try await forward(data, acknowledgement: acknowledgement, send: send)
                    // swiftlint:disable:next pattern_matching_keywords
                    case .finished(let turn, let result):
                        _ = try await group.next()
                        if let terminal = try finish(turn, result: result, state: &state) {
                            try await send(terminal)
                        }
                        await upstream?.release(turn.id)
                    // swiftlint:disable:next pattern_matching_keywords
                    case .checkpoint(let turn, let result, let input, let acknowledgement):
                        do {
                            try checkpoint(turn, result: result, input: input, state: &state)
                        } catch {
                            let failure =
                                (error as? ResponsesWebSocketFailure)
                                ?? ResponsesWebSocketFailure(
                                    status: 502, code: .invalidResponse, message: "Provider response checkpoint failed")
                            acknowledgement.finish(throwing: failure.identifyingStream(turn.streamID))
                            continue
                        }
                        try await forward(result.terminal, acknowledgement: acknowledgement, send: send)
                    case .readFailed(let error):
                        throw error
                    // swiftlint:disable:next pattern_matching_keywords
                    case .steered(let bytes, let result):
                        steeringQueue.complete(bytes: bytes)
                        if case .failure(let error) = result {
                            let failure =
                                (error as? ResponsesWebSocketFailure)
                                ?? ResponsesWebSocketFailure(
                                    status: 502, code: .upstreamError, message: "Could not forward steering")
                            try await send(failure.encoded())
                        }
                    case .expired:
                        try await send(
                            ResponsesWebSocketFailure(
                                status: 400,
                                code: .websocketConnectionLimitReached,
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
                                let result = await execute(turn, executor: executor, sink: sink)
                                await channel.send(.finished(turn, result))
                            }
                        }
                    }
                }
                channel.finish()
                steeringInput.finish()
                await upstream?.finish()
                group.cancelAll()
            } catch {
                channel.finish()
                steeringInput.finish()
                await upstream?.finish()
                group.cancelAll()
                throw error
            }
        }
    }

    private func enqueue(
        _ frame: Data,
        state: inout ResponsesWebSocketState,
        steeringQueue: inout ResponsesWebSocketSteeringQueue
    ) throws {
        let envelope = try ResponsesWebSocketRequest.Envelope(frame, maximumBytes: limits.maxFrameBytes)
        if envelope.isSteering, upstreamTransport != nil {
            try steeringQueue.enqueue(envelope)
        } else {
            try state.enqueue(envelope)
        }
    }

    private func expire(channel: AsyncChannel<Event>) async {
        do {
            try await Task.sleep(for: lifetime)
            await channel.send(.expired)
        } catch {}
    }

    private func forward(
        _ data: Data,
        acknowledgement: AsyncThrowingStream<Void, any Error>.Continuation,
        send: @Sendable (Data) async throws -> Void
    ) async throws {
        do {
            try await send(data)
            acknowledgement.finish()
        } catch {
            acknowledgement.finish(throwing: error)
            throw error
        }
    }

    private func read<Messages: AsyncSequence & Sendable>(
        _ messages: Messages, channel: AsyncChannel<Event>
    ) async where Messages.Element == Data {
        do {
            for try await message in messages {
                try Task.checkCancellation()
                await channel.send(.received(message))
            }
            await channel.send(.closed)
        } catch { await channel.send(.readFailed(error)) }
    }

    private func forwardSteering(
        _ messages: AsyncStream<ResponsesWebSocketSteering>,
        upstream: ResponsesUpstreamSession,
        channel: AsyncChannel<Event>
    ) async {
        for await steering in messages {
            let result: Result<Void, any Error>
            do {
                try await upstream.steer(steering)
                result = .success(())
            } catch { result = .failure(error) }
            await channel.send(.steered(steering.body.count, result))
        }
    }

    private func execute(
        _ turn: ResponsesWebSocketTurn, executor: ResponsesWebSocketExecutor, sink: Sink
    ) async -> Result<ResponsesWebSocketEventResult, any Error> {
        do {
            return .success(
                try await executor.execute(turn, emit: sink.send) { result, input in
                    try await sink.checkpoint(turn, result: result, input: input)
                })
        } catch { return .failure(error) }
    }

    private func checkpoint(
        _ turn: ResponsesWebSocketTurn,
        result: ResponsesWebSocketEventResult,
        input: [JSONValue],
        state: inout ResponsesWebSocketState
    ) throws {
        let completion = result.responseID.flatMap { identifier in
            result.output.map { ResponsesWebSocketCompletion(responseID: identifier, output: $0) }
        }
        try state.checkpoint(turn, completion: completion, appliedInput: input)
    }

    private func finish(
        _ turn: ResponsesWebSocketTurn,
        result: Result<ResponsesWebSocketEventResult, any Error>,
        state: inout ResponsesWebSocketState
    ) throws -> Data? {
        do {
            let completed = try result.get()
            if completed.published {
                state.releaseCheckpointed(turn)
                return nil
            }
            let context = completed.responseID.flatMap { identifier in
                completed.output.map { ResponsesWebSocketCompletion(responseID: identifier, output: $0) }
            }
            try state.finish(turn, completion: context)
            return completed.terminal
        } catch {
            if (error as? ResponsesWebSocketFailure)?.code == .pendingSteering {
                // No request was submitted. Retain the original checkpoint so
                // the client can return required input on its owning chain.
                state.releaseCheckpointed(turn)
            } else {
                try state.finish(turn, completion: nil)
            }
            let failure =
                (error as? ResponsesWebSocketFailure)
                ?? ResponsesWebSocketFailure(
                    status: 502,
                    code: .upstreamError,
                    message: "Provider response failed",
                    streamID: turn.streamID)
            return try failure.identifyingStream(turn.streamID).encoded()
        }
    }

    private enum Event: Sendable {
        case received(Data)
        case outbound(Data, AsyncThrowingStream<Void, any Error>.Continuation)
        case finished(ResponsesWebSocketTurn, Result<ResponsesWebSocketEventResult, any Error>)
        case checkpoint(
            ResponsesWebSocketTurn, ResponsesWebSocketEventResult, [JSONValue],
            AsyncThrowingStream<Void, any Error>.Continuation)
        case steered(Int, Result<Void, any Error>)
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

        func checkpoint(
            _ turn: ResponsesWebSocketTurn,
            result: ResponsesWebSocketEventResult,
            input: [JSONValue]
        ) async throws {
            let (acknowledgements, continuation) = AsyncThrowingStream<Void, any Error>.makeStream(
                bufferingPolicy: .bufferingOldest(1))
            await channel.send(.checkpoint(turn, result, input, continuation))
            for try await _ in acknowledgements {}
            try Task.checkCancellation()
        }
    }
}
