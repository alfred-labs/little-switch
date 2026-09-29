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
    private struct SteeringDeadline: Sendable {
        let identifier: UUID
        let instant: ContinuousClock.Instant
    }
    private enum Retirement: Error {
        case steeringAcknowledgementTimeout
    }
    private enum TerminalDisposition {
        case allowsAutomaticContinuation
        case requiresRequest
    }
    private enum RunEvent: Sendable {
        case connection(Result<Void, any Error>)
        case acknowledgementDeadline(Result<Void, any Error>)
        case closeRequested
    }
    package let key: ResponsesUpstreamKey
    private let request: UpstreamWebSocketRequest
    private let maximumBytes: Int
    private let maximumPendingSteers: Int
    private let steeringAcknowledgementTimeout: Duration
    private let validateSteering: @Sendable (ResponsesWebSocketSteering) throws -> Void
    private let control: @Sendable (Data) async throws -> Void
    private var outbound: (any UpstreamWebSocketOutbound)?
    private let readiness = ResponsesUpstreamReadiness()
    private let steeringDeadlines = AsyncStream<SteeringDeadline>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let closeRequests = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var steeringDeadlineID: UUID?
    private var failure: (any Error)?
    private var body: ResponsesUpstreamBody?
    private var submitted: [ResponsesWebSocketSteering] = []
    private var accepted: [(String, ResponsesWebSocketSteering)] = []
    private var applied: [String: [JSONValue]] = [:]
    private var retainedSteeringBytes = 0
    private var responseID: String?
    private var latestCompletedID: String?
    private var terminal: TerminalDisposition?
    private var waitsForTools = false
    private var validateProvider: @Sendable () async throws -> Void = {}
    private var observeControl: @Sendable (String) -> Void = { _ in }
    private var submittedObservers: [@Sendable (String) -> Void] = []
    private var acceptedObservers: [String: @Sendable (String) -> Void] = [:]

    package init(
        key: ResponsesUpstreamKey,
        request: UpstreamWebSocketRequest,
        maximumBytes: Int,
        maximumPendingSteers: Int = ResponsesWebSocketLimits().maxQueuedRequests,
        steeringAcknowledgementTimeout: Duration = ResponsesWebSocketLimits().steeringAcknowledgementTimeout,
        validateSteering: @escaping @Sendable (ResponsesWebSocketSteering) throws -> Void = { _ in },
        control: @escaping @Sendable (Data) async throws -> Void
    ) {
        self.key = key
        self.request = request
        self.maximumBytes = maximumBytes
        self.maximumPendingSteers = maximumPendingSteers
        self.steeringAcknowledgementTimeout = steeringAcknowledgementTimeout
        self.validateSteering = validateSteering
        self.control = control
    }

    package func run(transport: any UpstreamWebSocketTransport) async {
        guard failure == nil else { return }
        defer {
            steeringDeadlines.continuation.finish()
            closeRequests.continuation.finish()
        }
        do {
            try await withThrowingTaskGroup(of: RunEvent.self) { group in
                group.addTask { [request] in
                    do {
                        try await transport.withConnection(request) { try await self.consumeConnection($0) }
                        return .connection(.success(()))
                    } catch { return .connection(.failure(error)) }
                }
                group.addTask {
                    do {
                        try await self.monitorSteeringAcknowledgements()
                        return .acknowledgementDeadline(.success(()))
                    } catch { return .acknowledgementDeadline(.failure(error)) }
                }
                group.addTask { [closeRequests] in
                    for await _ in closeRequests.stream { return .closeRequested }
                    return .closeRequested
                }
                defer { group.cancelAll() }
                while let event = try await group.next() {
                    switch event {
                    case .closeRequested:
                        return
                    case .acknowledgementDeadline(let result):
                        try result.get()
                        return
                    case .connection(let result):
                        if await self.shouldDrainRetirement(after: result) { continue }
                        try result.get()
                        return
                    }
                }
            }
            await finishRun(UpstreamWebSocketFailure(kind: .connectionEnded))
        } catch { await finishRun(error) }
    }

    package func exchange(
        _ data: Data,
        previousResponseID: String?,
        observeControl: @escaping @Sendable (String) -> Void,
        validateProvider: @escaping @Sendable () async throws -> Void
    ) async throws -> HTTPClientResponse {
        try await readiness.wait()
        try await validateProvider()
        try Task.checkCancellation()
        guard failure == nil, body == nil, let outbound else {
            throw UpstreamWebSocketFailure(kind: .connectionClosing)
        }
        let channel = ResponsesUpstreamBody()
        body = channel
        terminal = nil
        waitsForTools = false
        responseID = nil
        self.validateProvider = validateProvider
        self.observeControl = observeControl
        // Steering can only be implicitly applied by the owning upstream chain.
        guard accepted.isEmpty || previousResponseID == latestCompletedID else {
            body = nil
            throw ResponsesWebSocketFailure(
                status: 409, code: .pendingSteering, message: "Continue the response with pending steering")
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
                code: .responseNotFound,
                message:
                    "The response provider is no longer available. Reconnect, replay complete portable history, and explicitly resubmit unapplied steering."
            )
        }
        guard failure == nil, let outbound,
            responseID == steering.previousResponseID, body != nil, terminal == nil
        else {
            throw ResponsesWebSocketFailure(
                status: 400, code: .responseNotFound, message: "The response is not active on this connection")
        }
        try validateSteering(steering)
        guard submitted.count + accepted.count < maximumPendingSteers,
            steering.body.count <= maximumBytes - retainedSteeringBytes
        else {
            throw ResponsesWebSocketFailure(
                status: 429, code: .tooManyPendingSteers, message: "Too much steering input is pending")
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
        closeRequests.continuation.yield(())
        await fail(CancellationError())
        try? await outbound?.close()
    }

    private func consumeConnection(_ connection: UpstreamWebSocketConnection) async throws {
        if let failure { throw failure }
        outbound = connection.outbound
        defer { outbound = nil }
        await readiness.resolve(.success(()))
        _ = try await connection.inbound.consume { try await self.receive($0) }
    }

    private func shouldDrainRetirement(after result: Result<Void, any Error>) async -> Bool {
        if let failure, failure is Retirement { return true }
        let error: any Error
        switch result {
        case .success: error = UpstreamWebSocketFailure(kind: .connectionEnded)
        case .failure(let cause): error = cause
        }
        // Mark the ordinary disconnect before suspension, so a retirement
        // cannot begin between this decision and cancelling the monitor.
        if beginFailure(error) { await completeFailure(error) }
        return false
    }

    private func fail(_ error: any Error) async {
        guard beginFailure(error) else { return }
        await completeFailure(error)
    }

    private func beginFailure(_ error: any Error) -> Bool {
        guard failure == nil else { return false }
        failure = error
        steeringDeadlineID = nil
        return true
    }

    private func completeFailure(_ error: any Error) async {
        let failedBody = body
        body = nil
        await failedBody?.fail(error)
        await readiness.resolve(.failure(error))
    }

    private func finishRun(_ error: any Error) async {
        // Only the run owner can finish an interrupted retirement. A concurrent
        // steer write failure must leave the body open until controls drain.
        if let failure, failure is Retirement {
            await finishBody()
        } else {
            await fail(error)
        }
    }
}

extension ResponsesUpstreamConnection {
    private func receive(_ message: UpstreamWebSocketMessage) async throws {
        try Task.checkCancellation()
        // Retirement rejects all new work before asynchronous control writes;
        // late acknowledgements cannot bind to another turn while those drain.
        guard failure == nil else { return }
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
            if responseID != nil, terminal == nil { throw ResponsesWebSocketEvents.Error.mismatchedResponse }
            responseID = identifier
            terminal = nil
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
        let disposition = Self.terminalDisposition(type)
        let terminalReceivedAt = disposition.map { _ in ContinuousClock.now }
        if let disposition {
            terminal = disposition
            latestCompletedID =
                event[EventKey.response.rawValue]?.object?[ResponseKey.id.rawValue]?.string ?? responseID
            waitsForTools =
                waitsForTools
                || (event[EventKey.response.rawValue]?.object?[ResponseKey.output.rawValue]?.array?.contains {
                    ResponsesClientToolContinuation.requiresInput($0)
                } ?? false)
        }
        let framed = try ServerSentEventEncoder.encode(data: data)
        try await body.send(ByteBuffer(bytes: framed))
        try Task.checkCancellation()
        if let terminalReceivedAt, !submitted.isEmpty, steeringDeadlineID == nil {
            let identifier = UUID()
            steeringDeadlineID = identifier
            steeringDeadlines.continuation.yield(
                SteeringDeadline(
                    identifier: identifier,
                    instant: terminalReceivedAt.advanced(by: steeringAcknowledgementTimeout)))
        }
        if shouldFinishBody { await finishBody() }
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
        if submitted.isEmpty { steeringDeadlineID = nil }
        try await control(data)
        if shouldFinishBody { await finishBody() }
    }

    private var shouldFinishBody: Bool {
        failure == nil && terminal != nil && submitted.isEmpty
            && (terminal == .requiresRequest || waitsForTools || accepted.isEmpty)
    }

    private static func terminalDisposition(_ type: String) -> TerminalDisposition? {
        switch type {
        case OpenAIResponsesCompletedEventType.responseCompleted.rawValue,
            OpenAIResponsesIncompleteEventType.responseIncomplete.rawValue:
            return .allowsAutomaticContinuation
        case OpenAIResponsesFailedEventType.responseFailed.rawValue, OpenAIResponsesErrorEventType.error.rawValue:
            return .requiresRequest
        default:
            return nil
        }
    }

    private func finishBody() async {
        await body?.finish()
        body = nil
    }

}

extension ResponsesUpstreamConnection {
    private func monitorSteeringAcknowledgements() async throws {
        for await deadline in steeringDeadlines.stream {
            // Deadlines are monotonic. A satisfied older timer may finish its
            // sleep before observing the newest buffered deadline, but cannot
            // delay that newer deadline or expire a different generation.
            try await ContinuousClock().sleep(until: deadline.instant)
            if try await expireSteeringAcknowledgements(deadline.identifier) { return }
        }
    }

    private func expireSteeringAcknowledgements(_ identifier: UUID) async throws -> Bool {
        guard failure == nil, steeringDeadlineID == identifier, !submitted.isEmpty else { return false }
        let failures =
            accepted.map { identifier, steering in
                ResponsesUpstreamSteeringFailure(
                    identifier: identifier,
                    previousResponseID: steering.previousResponseID,
                    code: .steeringConnectionRetired,
                    observer: acceptedObservers[identifier])
            }
            + zip(submitted, submittedObservers).map { steering, observer in
                ResponsesUpstreamSteeringFailure(
                    identifier: nil,
                    previousResponseID: steering.previousResponseID,
                    code: .steeringAcknowledgementTimeout,
                    observer: observer)
            }
        // Retire before suspending: neither a new turn nor a late upstream
        // acknowledgement may consume an intent from this expired generation.
        failure = Retirement.steeringAcknowledgementTimeout
        steeringDeadlineID = nil
        submitted.removeAll()
        submittedObservers.removeAll()
        accepted.removeAll()
        acceptedObservers.removeAll()
        retainedSteeringBytes = 0
        for failure in failures { failure.observer?(ResponsesWebSocketContract.Event.steerFailed.rawValue) }
        for failure in failures { try await control(failure.encoded()) }
        await finishBody()
        try? await outbound?.close()
        return true
    }
}
