import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket bounds")
struct ResponsesWebSocketBoundsTests {
    @Test("Accepted lane names remain reserved for the connection lifetime")
    func namedStreamLimit() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxNamedStreams = 2
        var state = ResponsesWebSocketState(limits: limits)
        try webSocketStateSeed(&state, stream: "first", responseID: "first")
        try webSocketStateSeed(&state, stream: "second", responseID: "second")
        let rejected = try webSocketStateEnqueueFailure(webSocketStateRequest(stream: "third"), state: &state)
        #expect(rejected.code == .websocketStreamLimitReached)
        try state.enqueue(webSocketStateRequest(stream: "first"))
        try state.enqueue(webSocketStateRequest())
        #expect(try webSocketStateTurn(&state).streamID == "first")
        #expect(try webSocketStateTurn(&state).streamID == nil)
    }

    @Test("Queue-count rejections neither register lanes nor retain capacity")
    func queuedRequestLimit() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxQueuedRequests = 1
        limits.maxNamedStreams = 2
        var state = ResponsesWebSocketState(limits: limits)
        try state.enqueue(webSocketStateRequest(stream: "first"))
        #expect(
            try webSocketStateEnqueueFailure(webSocketStateRequest(stream: "rejected"), state: &state).status == 429)
        let turn = try webSocketStateTurn(&state)
        try state.finish(turn, completion: nil)
        try state.enqueue(webSocketStateRequest(stream: "last"))
        #expect(try webSocketStateTurn(&state).streamID == "last")
    }

    @Test("Queued bytes are released when a request starts")
    func queuedByteLimit() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxQueuedBytes = 150
        var state = ResponsesWebSocketState(limits: limits)
        let request = try webSocketStateRequest(input: .string("hello"))
        try state.enqueue(request)
        #expect(try webSocketStateEnqueueFailure(request, state: &state).status == 429)
        _ = try webSocketStateTurn(&state)
        try state.enqueue(request)
    }

    @Test("Oversized frames never enter the queue")
    func frameLimit() async throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxFrameBytes = 64
        let websocket = SyntheticResponsesWebSocketTransport()
        let harness = try NativeResponsesSessionHarness(websocket: websocket, limits: limits)
        let task = harness.start()
        defer {
            harness.input.finish()
            task.cancel()
        }
        harness.input.yield(try webSocketStateRequest(input: .string(String(repeating: "a", count: 100))))
        let rejected = try await harness.events.wait(type: "error")
        #expect(rejected["status"] == 413)
        #expect(await websocket.requests.isEmpty)
        harness.enqueue(#"{"type":"response.create","model":"gpt-6-astra"}"#)
        _ = try await harness.events.wait(type: "response.completed")
        #expect(await websocket.requests.count == 1)
        harness.input.finish()
        try await valueWithinTimeout(task, description: "frame ingress limit cleanup")
    }

    @Test("Memory-blocked lane heads cannot be overtaken by their smaller followers")
    func activeMemoryFIFO() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxActiveBytes = 650
        var state = ResponsesWebSocketState(limits: limits)
        try state.enqueue(webSocketStateRequest(stream: "active", input: .string(String(repeating: "a", count: 100))))
        let active = try webSocketStateTurn(&state)
        try state.enqueue(webSocketStateRequest(stream: "blocked", input: .string(String(repeating: "b", count: 80))))
        try state.enqueue(webSocketStateRequest(stream: "blocked", input: .string("small follower")))
        try state.enqueue(webSocketStateRequest(stream: "other", input: .string("small")))
        let other = try webSocketStateTurn(&state)
        #expect(other.streamID == "other")
        #expect(state.next() == nil)
        try state.finish(active, completion: nil)
        let head = try webSocketStateTurn(&state)
        #expect(head.streamID == "blocked")
        let input = try webSocketStateInputData(head)
        #expect(String(data: input, encoding: .utf8)?.contains(String(repeating: "b", count: 80)) == true)
    }

    @Test("A request that cannot fit alone fails instead of blocking all lanes")
    func oversizedActiveRequest() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxActiveBytes = 150
        var state = ResponsesWebSocketState(limits: limits)
        try state.enqueue(webSocketStateRequest(input: .string("too large once normalized")))
        #expect(try webSocketStateRejection(state.next()).status == 413)
        try state.enqueue(webSocketStateRequest())
        let turn = try webSocketStateTurn(&state)
        #expect(try webSocketStateInputData(turn) == Data("[]".utf8))
    }

    @Test("The cache evicts a whole least-recently-used lane snapshot")
    func historyLRU() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxHistoryBytes = 200
        var state = ResponsesWebSocketState(limits: limits)
        try webSocketStateSeed(&state, stream: "first", responseID: "first", input: "a")
        try webSocketStateSeed(&state, stream: "second", responseID: "second", input: "b")
        try state.enqueue(webSocketStateRequest(stream: "reader", previous: "first"))
        let reader = try webSocketStateTurn(&state)
        try state.finish(reader, completion: nil)
        try webSocketStateSeed(&state, stream: "third", responseID: "third", input: "c")
        try state.enqueue(webSocketStateRequest(stream: "lookup", previous: "second"))
        #expect(try webSocketStateRejection(state.next()).code == .previousResponseNotFound)
        try state.enqueue(webSocketStateRequest(stream: "lookup", previous: "first"))
        #expect(try webSocketStateTurn(&state).previousResponseID == "first")
    }

    @Test("An oversized new history replaces the lane cache with no entry rather than truncation")
    func oversizedHistory() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxHistoryBytes = 20
        var state = ResponsesWebSocketState(limits: limits)
        try webSocketStateSeed(&state, stream: "main", responseID: "small")
        try webSocketStateSeed(&state, stream: "main", responseID: "large", input: "must never be truncated")
        for previous in ["small", "large"] {
            try state.enqueue(webSocketStateRequest(stream: "main", previous: previous))
            #expect(try webSocketStateRejection(state.next()).code == .previousResponseNotFound)
        }
    }

    @Test("Invalid or oversized completions release active capacity without caching output")
    func rejectedCompletion() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxResponseBytes = 8
        limits.maxActiveResponses = 1
        for output in [Data("[null]".utf8), Data("[{}] ".utf8) + Data(repeating: 0x20, count: 8)] {
            var state = ResponsesWebSocketState(limits: limits)
            try state.enqueue(webSocketStateRequest())
            let first = try webSocketStateTurn(&state)
            #expect(throws: ResponsesWebSocketFailure.self) {
                try state.finish(first, completion: .init(responseID: "invalid", output: output))
            }
            try state.enqueue(webSocketStateRequest())
            let second = try webSocketStateTurn(&state)
            #expect(second.id != first.id)
        }
    }
}
