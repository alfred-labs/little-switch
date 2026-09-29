import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Independent steering deadline phases", .timeLimit(.minutes(1)))
struct ResponsesUpstreamDeadlinePhaseTests {
    @Test("Both phase budgets are configurable independently")
    func configuredBudgets() async throws {
        var limits = ResponsesWebSocketLimits()
        limits.steeringAcknowledgementTimeout = .seconds(3)
        limits.steeringContinuationTimeout = .seconds(20)
        let fixture = try SteeringDeadlineFixture(limits: limits)
        let owner = fixture.run()
        let consumer = fixture.consume()
        defer {
            owner.cancel()
            consumer.cancel()
        }
        try await fixture.created("r1")
        try await fixture.submit()
        try await fixture.completed("r1")
        #expect(try await fixture.deadline(1) == .seconds(3))
        await fixture.clock.advance(by: .seconds(2))
        try await fixture.resolve("accepted", id: "s1")
        #expect(try await fixture.deadline(2) == .seconds(22))
        await fixture.clock.advance(by: .seconds(20))
        try await valueWithinTimeout(consumer, description: "configured continuation timeout")
        try await valueWithinTimeout(owner, description: "configured budgets cleanup")
        let failure = try await fixture.controls.wait(type: "response.steer.failed")
        #expect(failure["error"]?.object?["code"] == "steering_continuation_timeout")
    }

    @Test("Blocked control delivery pauses the remaining continuation budget, not a fresh one")
    func continuationDeliveryPause() async throws {
        let gate = AsyncTestGate()
        let fixture = try SteeringDeadlineFixture(pendingGate: gate)
        let owner = fixture.run()
        let consumer = fixture.consume()
        defer {
            owner.cancel()
            consumer.cancel()
        }
        try await fixture.created("r1")
        for id in ["s1", "s2"] {
            try await fixture.submit()
            try await fixture.resolve("accepted", id: id)
        }
        try await fixture.completed("r1")
        #expect(try await fixture.deadline(1) == .seconds(60))
        await fixture.clock.advance(by: .seconds(50))
        try await fixture.websocket.publish(
            #"{"type":"response.steer.pending","steer":{"id":"s1","previous_response_id":"r1"}}"#)
        _ = try await fixture.controls.wait(type: "response.steer.pending")
        await fixture.clock.advance(by: .seconds(20))
        await gate.open()
        #expect(try await fixture.deadline(2) == .seconds(80))
        #expect(await fixture.connection.usable)
        await fixture.clock.advance(by: .seconds(10))
        try await valueWithinTimeout(consumer, description: "paused continuation expires after remaining budget")
        try await valueWithinTimeout(owner, description: "paused continuation cleanup")
        let failures = try await fixture.controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 2)
        #expect(failures[0]["error"]?.object?["code"] == "steering_connection_retired")
        #expect(failures[1]["error"]?.object?["code"] == "steering_continuation_timeout")
    }

    @Test("A successor after the ACK window still has its continuation budget")
    func delayedSuccessor() async throws {
        let fixture = try SteeringDeadlineFixture()
        let owner = fixture.run()
        let consumer = fixture.consume()
        defer {
            owner.cancel()
            consumer.cancel()
        }
        try await fixture.created("r1")
        try await fixture.submit()
        try await fixture.resolve("accepted", id: "s1")
        try await fixture.completed("r1")
        try #require(await fixture.deadline(1) == .seconds(60))
        await fixture.clock.advance(by: .seconds(6))
        try await fixture.publish(#"{"type":"response.created","response":{"id":"r2","output":[]}}"#)
        try await fixture.completed("r2")
        try await valueWithinTimeout(consumer, description: "delayed but timely successor")
        #expect(await fixture.connection.usable)
        #expect(try await fixture.controls.values().compactMap { $0["type"]?.string } == ["response.steer.accepted"])
        #expect(
            try await fixture.events.values().compactMap { $0["response"]?.object?["id"]?.string }
                == ["r1", "r1", "r2", "r2"])
        await fixture.connection.close()
        try await valueWithinTimeout(owner, description: "delayed successor cleanup")
    }

    @Test("An absent successor expires with a continuation-specific failure")
    func absentSuccessor() async throws {
        let fixture = try SteeringDeadlineFixture()
        let owner = fixture.run()
        let consumer = fixture.consume()
        defer {
            owner.cancel()
            consumer.cancel()
        }
        try await fixture.created("r1")
        try await fixture.submit()
        try await fixture.resolve("accepted", id: "s1")
        try await fixture.completed("r1")
        #expect(try await fixture.deadline(1) == .seconds(60))
        await fixture.clock.advance(by: .seconds(60))
        try await valueWithinTimeout(consumer, description: "absent successor ends the body")
        try await valueWithinTimeout(owner, description: "absent successor retires the connection")
        let failures = try await fixture.controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 1)
        #expect(failures.first?["steer"]?.object?["id"] == "s1")
        #expect(failures.first?["error"]?.object?["code"] == "steering_continuation_timeout")
        #expect(await fixture.connection.usable == false)
    }

    @Test(
        "Partial acknowledgement preserves the ACK budget; the last resolution starts a full continuation budget",
        arguments: ["accepted", "failed", "pending"])
    func acknowledgementTransition(lastResolution: String) async throws {
        let fixture = try SteeringDeadlineFixture()
        let owner = fixture.run()
        let consumer = fixture.consume()
        defer {
            owner.cancel()
            consumer.cancel()
        }
        try await fixture.created("r1")
        try await fixture.submit()
        try await fixture.submit()
        try await fixture.completed("r1")
        #expect(try await fixture.deadline(1) == .seconds(5))
        await fixture.clock.advance(by: .seconds(2))
        try await fixture.resolve("accepted", id: "s1")
        #expect(try await fixture.deadline(2) == .seconds(5))
        await fixture.clock.advance(by: .seconds(2))
        try await fixture.resolve(lastResolution, id: lastResolution == "failed" ? nil : "s2")
        #expect(try await fixture.deadline(3) == .seconds(64))
        await fixture.clock.advance(by: .seconds(60))
        try await valueWithinTimeout(consumer, description: "full continuation window after last resolution")
        try await valueWithinTimeout(owner, description: "resolved ACK phase cleanup")
        let failures = try await fixture.controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.contains { $0["error"]?.object?["code"] == "steering_continuation_timeout" })
        #expect(failures.allSatisfy { $0["error"]?.object?["code"] != "steering_acknowledgement_timeout" })
    }

    @Test("A newer short ACK deadline interrupts an obsolete long continuation timer")
    func earlierReplacement() async throws {
        let fixture = try SteeringDeadlineFixture()
        let owner = fixture.run()
        let consumer = fixture.consume()
        defer {
            owner.cancel()
            consumer.cancel()
        }
        try await fixture.created("r1")
        try await fixture.submit()
        try await fixture.resolve("accepted", id: "s1")
        try await fixture.completed("r1")
        try #require(await fixture.deadline(1) == .seconds(60))
        await fixture.clock.advance(by: .seconds(1))
        try await fixture.resolve("pending", id: "s1")
        try await valueWithinTimeout(consumer, description: "pending tool releases first body")
        let next = fixture.consume(previous: "r1")
        defer { next.cancel() }
        try await fixture.created("r2", requestCount: 3)
        try await fixture.submit(previous: "r2")
        try await fixture.completed("r2")
        #expect(try await fixture.deadline(2) == .seconds(6))
        await fixture.clock.advance(by: .seconds(5))
        try await valueWithinTimeout(next, description: "short ACK expires before obsolete continuation")
        try await valueWithinTimeout(owner, description: "replaced timer cleanup")
        let failures = try await fixture.controls.values().filter { $0["type"] == "response.steer.failed" }
        #expect(failures.count == 1)
        #expect(failures.first?["steer"]?.object?["previous_response_id"] == "r2")
        #expect(failures.first?["error"]?.object?["code"] == "steering_acknowledgement_timeout")
        #expect(await fixture.connection.usable == false)
    }
}

private struct SteeringDeadlineFixture: Sendable {
    let clock = ResolverTestClock()
    let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
    let controls = WebSocketEventRecorder()
    let events = WebSocketEventRecorder()
    let connection: ResponsesUpstreamConnection

    init(limits: ResponsesWebSocketLimits = .init(), pendingGate: AsyncTestGate? = nil) throws {
        connection = ResponsesUpstreamConnection(
            key: .init(provider: nil, endpoint: "https://example.invalid/v1/responses", model: "model"),
            request: try UpstreamWebSocketRequest(url: #require(URL(string: "wss://example.invalid/v1/responses"))),
            maximumBytes: 4_096,
            steeringAcknowledgementTimeout: limits.steeringAcknowledgementTimeout,
            steeringContinuationTimeout: limits.steeringContinuationTimeout,
            clock: clock
        ) { [controls] data in
            await controls.append(data)
            if try JSONValue.parse(data).object?["type"] == "response.steer.pending" {
                try await pendingGate?.wait()
            }
        }
    }

    func run() -> Task<Void, Never> { Task { await connection.run(transport: websocket) } }

    func consume(previous: String? = nil) -> Task<Void, any Error> {
        Task {
            let response = try await connection.exchange(
                Data(#"{"type":"response.create","model":"model","input":[]}"#.utf8),
                previousResponseID: previous,
                observeControl: { _ in },
                validateProvider: {})
            for try await chunk in response.body {
                let text = try #require(String(bytes: chunk.readableBytesView, encoding: .utf8))
                let json = text.dropFirst("data: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                await events.append(Data(json.utf8))
            }
        }
    }

    func submit(previous: String = "r1") async throws {
        try await connection.steer(
            ResponsesWebSocketSteering(
                .init(
                    Data(#"{"type":"response.steer","previous_response_id":"\#(previous)","input":"smaller"}"#.utf8),
                    maximumBytes: 4_096)))
    }

    func created(_ id: String, requestCount: Int = 1) async throws {
        try await websocket.waitForRequests(requestCount)
        try await publish(#"{"type":"response.created","response":{"id":"\#(id)","output":[]}}"#)
    }

    func completed(_ id: String) async throws {
        try await publish(#"{"type":"response.completed","response":{"id":"\#(id)","output":[]}}"#)
    }

    func resolve(_ kind: String, id: String?) async throws {
        var steer: JSONObject = ["previous_response_id": "r1"]
        steer["id"] = id.map(JSONValue.string)
        let event: JSONValue = ["type": .string("response.steer." + kind), "steer": .object(steer)]
        try await publish(#require(String(data: event.serializedData(), encoding: .utf8)))
    }

    func publish(_ text: String) async throws {
        let count = await websocket.processedMessages
        try await websocket.publish(text)
        try await websocket.waitForMessages(count + 1)
    }

    func deadline(_ count: Int) async throws -> Duration {
        let registration = Task { try await clock.waitForSleeps(count) }
        defer { registration.cancel() }
        try await valueWithinTimeout(registration, description: "steering deadline registration")
        return try #require(await clock.deadlines.last).offset
    }
}
