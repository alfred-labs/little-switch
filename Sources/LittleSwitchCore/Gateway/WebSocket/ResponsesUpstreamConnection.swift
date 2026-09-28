import AsyncAlgorithms
import AsyncHTTPClient
import Foundation
import HTTPTypes
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore

/// One upstream reader owns event ordering. A response body is a rendezvous,
/// so provider reads cannot outrun the existing validation/traffic pipeline.
package actor ResponsesUpstreamConnection {
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias ResponseKey = OpenAIResponsesResponse.Key
    private typealias ItemKey = OpenAIResponsesOutputItemDoneEvent.Key
    private typealias SteeringField = ResponsesWebSocketContract.SteeringField
    private typealias ControlField = ResponsesWebSocketContract.ControlField
    package let key: ResponsesUpstreamKey
    private let request: UpstreamWebSocketRequest
    private let maximumBytes: Int
    private let control: @Sendable (Data) async throws -> Void
    private var outbound: (any UpstreamWebSocketOutbound)?
    private var ready: [CheckedContinuation<Void, any Error>] = []
    private var failure: (any Error)?
    private var body: ResponsesUpstreamBody?
    private var submitted: [ResponsesWebSocketSteering] = []
    private var accepted: [(String, ResponsesWebSocketSteering)] = []
    private var applied: [String: [JSONValue]] = [:]
    private var retainedSteeringBytes = 0
    private var responseID: String?
    private var latestCompletedID: String?
    private var terminal = false
    private var waitsForTools = false
    private var validateProvider: @Sendable () async throws -> Void = {}
    private var observeControl: @Sendable (String) -> Void = { _ in }
    private var submittedObservers: [@Sendable (String) -> Void] = []
    private var acceptedObservers: [String: @Sendable (String) -> Void] = [:]

    package init(
        key: ResponsesUpstreamKey,
        request: UpstreamWebSocketRequest,
        maximumBytes: Int,
        control: @escaping @Sendable (Data) async throws -> Void
    ) {
        self.key = key
        self.request = request
        self.maximumBytes = maximumBytes
        self.control = control
    }

    package func run(transport: any UpstreamWebSocketTransport) async {
        do {
            try await transport.withConnection(request) { connection in
                await self.connected(connection.outbound)
                _ = try await connection.inbound.consume { try await self.receive($0) }
            }
            await fail(UpstreamWebSocketFailure(kind: .connectionEnded))
        } catch { await fail(error) }
    }

    package func exchange(
        _ data: Data,
        previousResponseID: String?,
        observeControl: @escaping @Sendable (String) -> Void,
        validateProvider: @escaping @Sendable () async throws -> Void
    ) async throws -> HTTPClientResponse {
        try await waitUntilReady()
        try await validateProvider()
        try Task.checkCancellation()
        guard body == nil, let outbound else { throw UpstreamWebSocketFailure(kind: .connectionClosing) }
        let channel = ResponsesUpstreamBody()
        body = channel
        terminal = false
        waitsForTools = false
        responseID = nil
        self.validateProvider = validateProvider
        self.observeControl = observeControl
        // Steering can only be implicitly applied by the owning upstream chain.
        guard accepted.isEmpty || previousResponseID == latestCompletedID else {
            body = nil
            throw ResponsesWebSocketFailure(
                status: 409, code: "pending_steering", message: "Continue the response with pending steering")
        }
        guard let text = String(data: data, encoding: .utf8) else { throw ResponsesWebSocketEvents.Error.invalidEvent }
        do {
            try await outbound.send(.text(text))
        } catch {
            await fail(error)
            throw error
        }
        return HTTPClientResponse(
            status: .ok, headers: [HTTPField.Name.contentType.rawName: "text/event-stream"], body: .stream(channel))
    }

    package func canContinue(_ identifier: String) -> Bool {
        failure == nil && latestCompletedID == identifier
    }

    package var usable: Bool { failure == nil }
    package var hasPendingSteering: Bool { !submitted.isEmpty || !accepted.isEmpty }

    package func owns(_ identifier: String) -> Bool {
        failure == nil && (responseID == identifier || latestCompletedID == identifier)
    }

    package func steer(_ steering: ResponsesWebSocketSteering) async throws {
        try Task.checkCancellation()
        do { try await validateProvider() } catch is CancellationError { throw CancellationError() } catch {
            throw ResponsesWebSocketFailure(
                status: 409,
                code: "response_not_found",
                message:
                    "The response provider is no longer available. Reconnect, replay complete portable history, and explicitly resubmit unapplied steering."
            )
        }
        guard failure == nil, let outbound,
            responseID == steering.previousResponseID, body != nil, !terminal
        else {
            throw ResponsesWebSocketFailure(
                status: 400, code: "response_not_found", message: "The response is not active on this connection")
        }
        guard submitted.count + accepted.count < 128,
            steering.body.count <= maximumBytes - retainedSteeringBytes
        else {
            throw ResponsesWebSocketFailure(
                status: 429, code: "too_many_pending_steers", message: "Too much steering input is pending")
        }
        submitted.append(steering)
        submittedObservers.append(observeControl)
        retainedSteeringBytes += steering.body.count
        observeControl(ResponsesWebSocketContract.Event.steerSubmitted.rawValue)
        guard let text = String(data: steering.body, encoding: .utf8) else {
            throw ResponsesWebSocketEvents.Error.invalidEvent
        }
        do { try await outbound.send(.text(text)) } catch {
            await fail(error)
            throw error
        }
    }

    package func takeAppliedInput(responseID: String) -> [JSONValue] {
        applied.removeValue(forKey: responseID) ?? []
    }

    package func close() async {
        await fail(CancellationError())
        try? await outbound?.close()
    }

    private func connected(_ outbound: any UpstreamWebSocketOutbound) {
        self.outbound = outbound
        let waiters = ready
        ready.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func waitUntilReady() async throws {
        if let failure { throw failure }
        if outbound != nil { return }
        try await withCheckedThrowingContinuation { ready.append($0) }
    }

    private func fail(_ error: any Error) async {
        guard failure == nil else { return }
        failure = error
        await body?.fail(error)
        body = nil
        let waiters = ready
        ready.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }

    private func receive(_ message: UpstreamWebSocketMessage) async throws {
        try Task.checkCancellation()
        guard case .text(let text) = message, text.utf8.count <= maximumBytes,
            let event = try JSONValue.parse(text).object, let type = event[EventKey.type.rawValue]?.string
        else { throw ResponsesWebSocketEvents.Error.invalidEvent }
        // WS JSON may contain physical newlines. Preserve exact JSON values
        // while putting each event on one valid SSE data line.
        let data = try JSONValue.object(event).serializedData()
        if type.hasPrefix(ResponsesWebSocketContract.Event.steer.rawValue + ".") {
            try await steeringEvent(event, type: type, data: data)
            return
        }
        guard let body else { throw ResponsesWebSocketEvents.Error.eventAfterTerminal }
        if type == OpenAIResponsesCreatedEventType.responseCreated.rawValue {
            guard let identifier = event[EventKey.response.rawValue]?.object?[ResponseKey.id.rawValue]?.string else {
                throw ResponsesWebSocketEvents.Error.invalidEvent
            }
            if responseID != nil, !terminal { throw ResponsesWebSocketEvents.Error.mismatchedResponse }
            responseID = identifier
            terminal = false
            waitsForTools = false
            if !accepted.isEmpty {
                applied[identifier] = accepted.flatMap(\.1.input)
                retainedSteeringBytes -= accepted.reduce(0) { $0 + $1.1.body.count }
                accepted.removeAll()
                acceptedObservers.removeAll()
            }
        }
        let itemDone = type == OpenAIResponsesOutputItemDoneEventType.responseOutputItemDone.rawValue
        if itemDone, let item = event[ItemKey.item.rawValue] {
            waitsForTools = waitsForTools || ResponsesClientToolContinuation.requiresInput(item)
        }
        let isTerminal = [
            OpenAIResponsesCompletedEventType.responseCompleted.rawValue,
            OpenAIResponsesIncompleteEventType.responseIncomplete.rawValue,
            OpenAIResponsesFailedEventType.responseFailed.rawValue, OpenAIResponsesErrorEventType.error.rawValue,
        ].contains(type)
        if isTerminal {
            terminal = true
            latestCompletedID =
                event[EventKey.response.rawValue]?.object?[ResponseKey.id.rawValue]?.string ?? responseID
            waitsForTools =
                waitsForTools
                || (event[EventKey.response.rawValue]?.object?[ResponseKey.output.rawValue]?.array?.contains {
                    ResponsesClientToolContinuation.requiresInput($0)
                } ?? false)
        }
        var framed = Data("data: ".utf8)
        framed.append(data)
        framed.append(Data("\n\n".utf8))
        try await body.send(ByteBuffer(bytes: framed))
        try Task.checkCancellation()
        let cannotContinue =
            type == OpenAIResponsesFailedEventType.responseFailed.rawValue
            || type == OpenAIResponsesErrorEventType.error.rawValue || waitsForTools
        let hasSteering = !accepted.isEmpty || !submitted.isEmpty
        if isTerminal, cannotContinue || !hasSteering { await finishBody() }
    }

    private func steeringEvent(_ event: JSONObject, type: String, data: Data) async throws {
        let steer = event[ControlField.steer.rawValue]?.object
        switch type {
        case ResponsesWebSocketContract.Event.steerAccepted.rawValue:
            guard let identifier = steer?[SteeringField.id.rawValue]?.string, !submitted.isEmpty,
                steer?[SteeringField.previousResponseID.rawValue]?.string == submitted[0].previousResponseID
            else { throw ResponsesWebSocketEvents.Error.invalidEvent }
            accepted.append((identifier, submitted.removeFirst()))
            let observer = submittedObservers.removeFirst()
            acceptedObservers[identifier] = observer
            observer(type)
        case ResponsesWebSocketContract.Event.steerFailed.rawValue:
            let identifier = steer?[SteeringField.id.rawValue]?.string
            if let identifier, let index = accepted.firstIndex(where: { $0.0 == identifier }) {
                retainedSteeringBytes -= accepted.remove(at: index).1.body.count
                acceptedObservers.removeValue(forKey: identifier)?(type)
            } else if steer?[SteeringField.id.rawValue] == nil, !submitted.isEmpty {
                retainedSteeringBytes -= submitted.removeFirst().body.count
                submittedObservers.removeFirst()(type)
            } else {
                throw ResponsesWebSocketEvents.Error.invalidEvent
            }
        case ResponsesWebSocketContract.Event.steerPending.rawValue:
            guard let identifier = steer?[SteeringField.id.rawValue]?.string,
                accepted.contains(where: { $0.0 == identifier })
            else { throw ResponsesWebSocketEvents.Error.invalidEvent }
            waitsForTools = true
            acceptedObservers[identifier]?(type)
        default:
            throw ResponsesWebSocketEvents.Error.invalidEvent
        }
        try await control(data)
        if terminal && (waitsForTools || (accepted.isEmpty && submitted.isEmpty)) { await finishBody() }
    }

    private func finishBody() async {
        await body?.finish()
        body = nil
    }

}

/// Acknowledgement occurs when the consumer asks for the next chunk, after the
/// current event passed all wrappers and its public checkpoint was published.
private actor ResponsesUpstreamBody: AsyncSequence {
    fileprivate struct Chunk: Sendable {
        let buffer: ByteBuffer
        let acknowledgement: AsyncStream<Void>.Continuation
    }
    private let channel = AsyncThrowingChannel<Chunk, any Error>()
    private var pending: AsyncStream<Void>.Continuation?

    func send(_ buffer: ByteBuffer) async throws {
        let (stream, acknowledgement) = AsyncStream<Void>.makeStream()
        pending = acknowledgement
        await channel.send(Chunk(buffer: buffer, acknowledgement: acknowledgement))
        for await _ in stream {}
        pending = nil
        try Task.checkCancellation()
    }

    func finish() {
        channel.finish()
        pending?.finish()
        pending = nil
    }
    func fail(_ error: any Error) {
        channel.fail(error)
        pending?.finish()
        pending = nil
    }

    nonisolated func makeAsyncIterator() -> AsyncIterator { AsyncIterator(source: channel.makeAsyncIterator()) }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var source: AsyncThrowingChannel<Chunk, any Error>.Iterator
        private var previous: AsyncStream<Void>.Continuation?

        fileprivate init(source: AsyncThrowingChannel<Chunk, any Error>.Iterator) { self.source = source }

        mutating func next() async throws -> ByteBuffer? {
            previous?.finish()
            previous = nil
            guard let chunk = try await source.next() else { return nil }
            previous = chunk.acknowledgement
            return chunk.buffer
        }
    }
}
