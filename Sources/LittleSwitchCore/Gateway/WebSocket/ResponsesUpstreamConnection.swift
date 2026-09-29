import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore

/// One upstream reader owns event ordering. A response body is a rendezvous,
/// so provider reads cannot outrun the existing validation/traffic pipeline.
package actor ResponsesUpstreamConnection {
    private typealias EventKey = OpenAIResponsesCreatedEvent.Key
    private typealias ResponseKey = OpenAIResponsesResponse.Key
    private typealias ItemKey = OpenAIResponsesOutputItemDoneEvent.Key
    private struct SteeringDeadline: Sendable {
        let identifier: UUID
        let instant: ResponsesUpstreamClock.Instant
    }
    private enum Retirement: Error {
        case steeringAcknowledgementTimeout
        case failedTerminal
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
    private let closeGrace: Duration
    private let clock: ResponsesUpstreamClock
    private let validateSteering: @Sendable (ResponsesWebSocketSteering) throws -> Void
    private let control: @Sendable (Data) async throws -> Void
    private var outbound: (any UpstreamWebSocketOutbound)?
    private let readiness = ResponsesUpstreamReadiness<Void>()
    private let steeringDeadlines = AsyncStream<SteeringDeadline>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let closeRequests = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let reportingStops = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let reportsFinished = ResponsesUpstreamReadiness<Void>()
    private var runStarted = false
    private var reportingDisabled = false
    private var pendingReports: [ResponsesUpstreamSteeringFailure] = []
    private var terminalToDeliver: ByteBuffer?
    private var steeringDeadline: SteeringDeadline?
    private var failure: (any Error)?
    private var body: ResponsesUpstreamBody?
    private var receivedResponseEvent = false
    private var steering = ResponsesUpstreamSteeringLedger()
    private var responseID: String?
    private var latestCompletedID: String?
    private var terminal: TerminalDisposition?
    private var waitsForTools = false
    private var validateProvider: @Sendable () async throws -> Void = {}
    private var observeControl: @Sendable (String) -> Void = { _ in }

    package init<C: Clock>(
        key: ResponsesUpstreamKey,
        request: UpstreamWebSocketRequest,
        maximumBytes: Int,
        maximumPendingSteers: Int = ResponsesWebSocketLimits().maxQueuedRequests,
        steeringAcknowledgementTimeout: Duration = ResponsesWebSocketLimits().steeringAcknowledgementTimeout,
        closeGrace: Duration = .seconds(ResponsesWebSocketLimits().closeGraceSeconds),
        clock: C = ContinuousClock(),
        validateSteering: @escaping @Sendable (ResponsesWebSocketSteering) throws -> Void = { _ in },
        control: @escaping @Sendable (Data) async throws -> Void
    ) where C.Duration == Duration {
        self.key = key
        self.request = request
        self.maximumBytes = maximumBytes
        self.maximumPendingSteers = maximumPendingSteers
        self.steeringAcknowledgementTimeout = steeringAcknowledgementTimeout
        self.closeGrace = closeGrace
        self.clock = ResponsesUpstreamClock(clock)
        self.validateSteering = validateSteering
        self.control = control
    }

    package func run(transport: any UpstreamWebSocketTransport) async {
        guard failure == nil else { return }
        runStarted = true
        defer {
            steeringDeadlines.continuation.finish()
            closeRequests.continuation.finish()
            reportingStops.continuation.finish()
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
                    for await _ in closeRequests.stream {
                        await self.closeTransport()
                        return .closeRequested
                    }
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
        receivedResponseEvent = false
        terminal = nil
        waitsForTools = false
        responseID = nil
        self.validateProvider = validateProvider
        self.observeControl = observeControl
        // Steering can only be implicitly applied by the owning upstream chain.
        guard !steering.hasAccepted || previousResponseID == latestCompletedID else {
            body = nil
            throw ResponsesWebSocketFailure(
                status: 409, code: .pendingSteering, message: "Continue the response with pending steering")
        }
        guard let text = String(data: data, encoding: .utf8) else { throw ResponsesWebSocketEvents.Error.invalidEvent }
        do {
            try await outbound.send(.text(text))
            return try await channel.response()
        } catch {
            await fail(error)
            throw error
        }
    }

    package func canContinue(_ identifier: String) -> Bool {
        failure == nil && latestCompletedID == identifier
    }

    package var usable: Bool { failure == nil }
    package var hasPendingSteering: Bool { steering.hasSubmitted || steering.hasAccepted }

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
        guard self.steering.count < maximumPendingSteers,
            steering.body.count <= maximumBytes - self.steering.retainedBytes
        else {
            throw ResponsesWebSocketFailure(
                status: 429, code: .tooManyPendingSteers, message: "Too much steering input is pending")
        }
        self.steering.submit(steering, observer: observeControl)
        guard let text = String(data: steering.body, encoding: .utf8) else {
            throw ResponsesWebSocketEvents.Error.invalidEvent
        }
        do { try await outbound.send(.text(text)) } catch {
            await fail(error)
            throw error
        }
    }

    package func takeAppliedInput(responseID: String) -> [JSONValue] {
        steering.takeAppliedInput(responseID: responseID)
    }

    package func close() async {
        await fail(CancellationError())
    }

    /// The downstream session is disappearing. Do not enqueue any new socket
    /// control writes, and interrupt a drain already waiting for downstream.
    package func cancel() async {
        reportingDisabled = true
        reportingStops.continuation.yield(())
        _ = beginFailure(CancellationError())
        await completeFailure(CancellationError())
    }

    private func consumeConnection(_ connection: UpstreamWebSocketConnection) async throws {
        if let failure { throw failure }
        outbound = connection.outbound
        defer { outbound = nil }
        await readiness.resolve(.success(()))
        _ = try await connection.inbound.consume { try await self.receive($0) }
    }

    private func closeTransport() async {
        // Explicit close/abort preserves the transport's ordered close write
        // and its own bounded close deadline. Retirement instead aborts the
        // reader immediately so no late acknowledgement can reuse this lane.
        guard !(failure is Retirement), !Task.isCancelled else { return }
        try? await outbound?.close()
    }

    private func fail(_ error: any Error) async {
        _ = beginFailure(error)
        if !runStarted { await completeFailure(error) }
        // The run owner drains controls before any turn or submission error.
        // Its drain is bounded and caller cancellation does not own that drain.
        try? await reportsFinished.wait()
    }

    private func beginFailure(
        _ error: any Error, submittedCode: ResponsesWebSocketContract.ErrorCode = .steeringConnectionRetired
    ) -> Bool {
        guard failure == nil else { return false }
        failure = error
        steeringDeadline = nil
        pendingReports = steering.takeFailures(submittedCode: submittedCode)
        for report in pendingReports { report.observer?(ResponsesWebSocketContract.Event.steerFailed.rawValue) }
        closeRequests.continuation.yield(())
        return true
    }

    private func completeFailure(_ error: any Error) async {
        let failedBody = body
        body = nil
        let terminal = terminalToDeliver
        terminalToDeliver = nil
        await reportsFinished.resolve(.success(()))
        if failure is Retirement, !reportingDisabled, !Task.isCancelled {
            do {
                if let terminal { try await failedBody?.send(terminal) }
                await failedBody?.finish()
            } catch { await failedBody?.fail(error) }
        } else {
            await failedBody?.fail(Task.isCancelled ? CancellationError() : error)
        }
        await readiness.resolve(.failure(error))
    }

    private func finishRun(_ error: any Error) async {
        _ = beginFailure(error)
        let reports = pendingReports
        pendingReports.removeAll()
        if !reportingDisabled, !Task.isCancelled {
            try? await ResponsesSteeringFailureDrain.run(
                reports,
                clock: clock,
                timeout: closeGrace,
                stop: reportingStops.stream
            ) { try await self.sendRetirementControl($0) }
        }
        await completeFailure(failure ?? error)
    }

    private func sendRetirementControl(_ data: Data) async throws {
        try Task.checkCancellation()
        guard !reportingDisabled else { throw CancellationError() }
        try await control(data)
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
        if !receivedResponseEvent, type == OpenAIResponsesErrorEventType.error.rawValue {
            let rejection = try ResponsesUpstreamRejection(event)
            // Release the exchange before publishing its headers: the caller
            // may immediately retry, including a text-only image projection.
            self.body = nil
            await body.reject(rejection)
            return
        }
        receivedResponseEvent = true
        if type == OpenAIResponsesCreatedEventType.responseCreated.rawValue {
            guard let identifier = event[EventKey.response.rawValue]?.object?[ResponseKey.id.rawValue]?.string else {
                throw ResponsesWebSocketEvents.Error.invalidEvent
            }
            if responseID != nil, terminal == nil { throw ResponsesWebSocketEvents.Error.mismatchedResponse }
            responseID = identifier
            terminal = nil
            waitsForTools = false
            steering.apply(to: identifier)
            if !steering.hasSubmitted { steeringDeadline = nil }
        }
        let itemDone = type == OpenAIResponsesOutputItemDoneEventType.responseOutputItemDone.rawValue
        if itemDone, let item = event[ItemKey.item.rawValue] {
            waitsForTools = waitsForTools || ResponsesClientToolContinuation.requiresInput(item)
        }
        let disposition = Self.terminalDisposition(type)
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
        if disposition == .requiresRequest, hasPendingSteering {
            terminalToDeliver = ByteBuffer(bytes: framed)
            _ = beginFailure(Retirement.failedTerminal)
            return
        }
        let remaining = pauseSteeringDeadline()
        try await body.send(ByteBuffer(bytes: framed))
        try Task.checkCancellation()
        resumeSteeringDeadline(remaining)
        // The sole upstream reader cannot read an acknowledgement while the
        // terminal is backpressured by downstream validation or delivery.
        if disposition != nil, awaitsSteeringProgress, steeringDeadline == nil {
            resumeSteeringDeadline(steeringAcknowledgementTimeout)
        }
        if shouldFinishBody { await finishBody() }
    }

    private func steeringEvent(_ event: JSONObject, type: String, data: Data) async throws {
        try steering.receive(event, type: type)
        let remaining = pauseSteeringDeadline()
        try await control(data)
        resumeSteeringDeadline(remaining)
        if shouldFinishBody { await finishBody() }
    }

    private var shouldFinishBody: Bool {
        failure == nil && terminal != nil && !steering.hasSubmitted
            && !awaitsAutomaticContinuation
    }

    private var awaitsAutomaticContinuation: Bool {
        terminal == .allowsAutomaticContinuation && !waitsForTools
            && steering.awaitsContinuation
    }

    private var awaitsSteeringProgress: Bool {
        steering.hasSubmitted || awaitsAutomaticContinuation
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
    /// While the sole reader delivers downstream it cannot read a buffered
    /// acknowledgement or successor. Resume the remaining budget, not a fresh
    /// timeout; replacement deadlines stay monotonic for the single monitor.
    private func pauseSteeringDeadline() -> Duration? {
        let remaining = steeringDeadline.map { max(.zero, clock.now.duration(to: $0.instant)) }
        steeringDeadline = nil
        return remaining
    }

    private func resumeSteeringDeadline(_ remaining: Duration?) {
        guard failure == nil, awaitsSteeringProgress, let remaining else { return }
        let deadline = SteeringDeadline(identifier: UUID(), instant: clock.now.advanced(by: remaining))
        steeringDeadline = deadline
        steeringDeadlines.continuation.yield(deadline)
    }

    private func monitorSteeringAcknowledgements() async throws {
        for await deadline in steeringDeadlines.stream {
            // Deadlines are monotonic. A satisfied older timer may finish its
            // sleep before observing the newest buffered deadline, but cannot
            // delay that newer deadline or expire a different generation.
            try await clock.sleep(until: deadline.instant)
            if expireSteeringAcknowledgements(deadline.identifier) { return }
        }
    }

    private func expireSteeringAcknowledgements(_ identifier: UUID) -> Bool {
        guard failure == nil, steeringDeadline?.identifier == identifier, awaitsSteeringProgress else { return false }
        return beginFailure(Retirement.steeringAcknowledgementTimeout, submittedCode: .steeringAcknowledgementTimeout)
    }

}
