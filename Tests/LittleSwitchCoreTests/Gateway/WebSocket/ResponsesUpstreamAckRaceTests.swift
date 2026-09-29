import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native steering acknowledgement races", .timeLimit(.minutes(1)))
struct ResponsesUpstreamAckRaceTests {
    @Test(
        "Joining a cancelled transport scope before retirement still drains every failure",
        arguments: [false, true])
    func disconnectDuringRetirement(cancelsTransportScope: Bool) async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let controlGate = AsyncTestGate()
        let controlCancelled = AsyncTestGate()
        let inboundEnded = AsyncTestGate()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) { data in
            await controls.append(data)
            let failures = try await controls.values().filter { $0["type"] == "response.steer.failed" }
            if failures.count == 1 {
                do { try await controlGate.wait() } catch {
                    await controlCancelled.open()
                    throw error
                }
            }
        }
        let transport = AcknowledgementObservedTransport(
            base: websocket, inboundEnded: inboundEnded, cancelsScopeOnDisconnect: cancelsTransportScope)
        let runner = Task { await connection.run(transport: transport) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            for try await _ in response.body { await received.open() }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before retirement drain")
        try await connection.steer(steering())
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.accepted")
        try await connection.steer(steering())
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        _ = try await controls.wait(type: "response.steer.failed")
        #expect(await inboundEnded.isOpen)
        #expect(await controlCancelled.isOpen == false)
        await controlGate.open()
        try await valueWithinTimeout(consumer, description: "retirement body after upstream disconnect")
        try await valueWithinTimeout(runner, description: "retirement drain after upstream disconnect")
        let failures = try await controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 2)
        #expect(failures.first?["error"]?.object?["code"] == "steering_connection_retired")
        #expect(failures.last?["error"]?.object?["code"] == "steering_acknowledgement_timeout")
        #expect(await websocket.activeConnections == 0)
    }

    @Test("Closing the owner joins a suspended retirement drain", arguments: [false, true])
    func cancelOwnerDuringRetirement(explicitClose: Bool) async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let controlGate = AsyncTestGate()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) {
            await controls.append($0)
            try await controlGate.wait()
        }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            for try await _ in response.body { await received.open() }
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before owner cancellation")
        try await connection.steer(steering())
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        _ = try await controls.wait(type: "response.steer.failed")
        if explicitClose {
            let close = Task { await connection.close() }
            try await clock.waitForSleeps(2)
            await clock.advance(by: .seconds(5))
            try await valueWithinTimeout(close, description: "explicit retirement close")
        } else {
            runner.cancel()
        }
        try await valueWithinTimeout(runner, description: "cancelled retirement owner")
        if explicitClose {
            try await valueWithinTimeout(consumer, description: "closed retirement body")
        } else {
            await #expect(throws: CancellationError.self) {
                try await valueWithinTimeout(consumer, description: "cancelled retirement body")
            }
        }
        #expect(await websocket.activeConnections == 0)
    }

    @Test("A failed steering write cannot finish the body before retirement controls drain")
    func failedWriteDuringRetirement() async throws {
        let clock = ResolverTestClock()
        let writeGate = AsyncTestGate()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false, steerGate: writeGate)
        let controls = WebSocketEventRecorder()
        let controlGate = AsyncTestGate()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) {
            await controls.append($0)
            try await controlGate.wait()
        }
        let transport = RetirementFailingWriteTransport(base: websocket)
        let runner = Task { await connection.run(transport: transport) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            for try await _ in response.body { await received.open() }
            #expect(await controlGate.isOpen)
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before failed steering write")
        let write = Task { try await connection.steer(steering()) }
        defer { write.cancel() }
        try await websocket.waitForRequests(2)
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        _ = try await controls.wait(type: "response.steer.failed")
        await writeGate.open()
        await controlGate.open()
        #expect(
            try await valueWithinTimeout(write, description: "failed steering write during retirement")
                == .connectionOwnedFailure)
        try await valueWithinTimeout(consumer, description: "body after failed write retirement drain")
        try await valueWithinTimeout(runner, description: "connection after failed write retirement drain")
        #expect(try await controls.values().count == 1)
        #expect(await websocket.activeConnections == 0)
    }

    @Test("Delivered acceptance leaves submitted steering bounded and failures drain before the body finishes")
    func acceptedControlResumesDuringRetirement() async throws {
        let clock = ResolverTestClock()
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let controls = WebSocketEventRecorder()
        let acceptedGate = AsyncTestGate()
        let failedGate = AsyncTestGate()
        let connection = try makeConnection(timeout: .seconds(5), clock: clock) { data in
            await controls.append(data)
            switch try JSONValue.parse(data).object?["type"]?.string {
            case "response.steer.accepted": try await acceptedGate.wait()
            case "response.steer.failed": try await failedGate.wait()
            default: break
            }
        }
        let runner = Task { await connection.run(transport: websocket) }
        defer { runner.cancel() }
        let responseTask = Task {
            try await connection.exchange(
                create, previousResponseID: nil, observeControl: { _ in }, validateProvider: {})
        }
        defer { responseTask.cancel() }
        let received = AsyncTestGate()
        let consumer = Task {
            let response = try await responseTask.value
            for try await _ in response.body { await received.open() }
            #expect(await failedGate.isOpen)
        }
        defer { consumer.cancel() }
        try await websocket.waitForRequests(1)
        try await websocket.publish(#"{"type":"response.created","response":{"id":"r1","output":[]}}"#)
        try await received.wait(description: "created response before suspended steering acknowledgement")
        try await connection.steer(steering())
        try await connection.steer(steering())
        try await websocket.publish(#"{"type":"response.completed","response":{"id":"r1","output":[]}}"#)
        try await websocket.publish(
            #"{"type":"response.steer.accepted","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await controls.wait(type: "response.steer.accepted")
        await acceptedGate.open()
        try await websocket.waitForMessages(3)
        try await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(5))
        _ = try await controls.wait(type: "response.steer.failed")
        await failedGate.open()
        try await valueWithinTimeout(consumer, description: "body after resumed acknowledgement and retirement")
        try await valueWithinTimeout(runner, description: "retired connection after resumed acknowledgement")
        #expect(try await controls.values().filter { $0["type"] == "response.steer.failed" }.count == 2)
        #expect(await websocket.activeConnections == 0)
    }

    private var create: Data {
        Data(#"{"type":"response.create","model":"gpt-6-astra","input":[]}"#.utf8)
    }

    private func steering() throws -> ResponsesWebSocketSteering {
        try ResponsesWebSocketSteering(
            .init(
                Data(#"{"type":"response.steer","previous_response_id":"r1","input":"smaller"}"#.utf8),
                maximumBytes: 4_096))
    }

    private func makeConnection(
        timeout: Duration,
        clock: ResolverTestClock = ResolverTestClock(),
        control: @escaping @Sendable (Data) async throws -> Void
    ) throws -> ResponsesUpstreamConnection {
        let url = try #require(URL(string: "wss://example.invalid/v1/responses"))
        return ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "gpt-6-astra"),
            request: try UpstreamWebSocketRequest(url: url),
            maximumBytes: 4_096,
            steeringAcknowledgementTimeout: timeout,
            clock: clock,
            control: control)
    }
}

private struct AcknowledgementObservedTransport: UpstreamWebSocketTransport {
    let base: SyntheticResponsesWebSocketTransport
    let inboundEnded: AsyncTestGate
    let cancelsScopeOnDisconnect: Bool

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        try await base.withConnection(request) { connection in
            let observed = UpstreamWebSocketConnection(
                handshake: connection.handshake,
                inbound: AcknowledgementObservedInbound(base: connection.inbound, ended: inboundEnded),
                outbound: connection.outbound)
            if cancelsScopeOnDisconnect {
                // NIO's abort signal cancels the operation scope on a read
                // failure; this is stronger than merely ending consume().
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await operation(observed) }
                    group.addTask {
                        try await inboundEnded.wait()
                        throw UpstreamWebSocketFailure(kind: .connectionLost)
                    }
                    defer { group.cancelAll() }
                    try await group.next()
                }
            } else {
                try await operation(observed)
            }
        }
    }

    func shutdown() async throws { try await base.shutdown() }
}

private struct AcknowledgementObservedInbound: UpstreamWebSocketInbound {
    let base: any UpstreamWebSocketInbound
    let ended: AsyncTestGate

    func consume(
        _ onMessage: @escaping @Sendable (UpstreamWebSocketMessage) async throws -> Void
    ) async throws -> UpstreamWebSocketPeerClose {
        do {
            let result = try await base.consume(onMessage)
            await ended.open()
            return result
        } catch {
            await ended.open()
            throw error
        }
    }
}

private struct RetirementFailingWriteTransport: UpstreamWebSocketTransport {
    let base: SyntheticResponsesWebSocketTransport

    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        try await base.withConnection(request) { connection in
            try await operation(
                .init(
                    handshake: connection.handshake,
                    inbound: connection.inbound,
                    outbound: RetirementFailingWriter(base: connection.outbound)))
        }
    }

    func shutdown() async throws { try await base.shutdown() }
}

private struct RetirementFailingWriter: UpstreamWebSocketOutbound {
    let base: any UpstreamWebSocketOutbound

    func send(_ message: UpstreamWebSocketMessage) async throws {
        try await base.send(message)
        if case .text(let text) = message, try JSONValue.parse(text).object?["type"] == "response.steer" {
            throw UpstreamWebSocketSendFailure(submission: .mayHaveBeenSubmitted, cause: .init(kind: .writeFailed))
        }
    }

    func close(code: UInt16, reason: String?) async throws { try await base.close(code: code, reason: reason) }
}
