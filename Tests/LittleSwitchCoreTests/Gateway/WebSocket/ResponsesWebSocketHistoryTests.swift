import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket history")
struct ResponsesWebSocketHistoryTests {
    @Test("Reusing a lane without a parent starts fresh and replaces its latest cache entry")
    func freshLaneTurn() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(&state, stream: "main", responseID: "old", input: "old")
        try state.enqueue(webSocketStateRequest(stream: "main", input: "new"))
        let fresh = try webSocketStateTurn(&state)
        #expect(try #require(JSONValue.parse(webSocketStateInputData(fresh)).array).count == 1)
        try state.finish(fresh, completion: .init(responseID: "new", output: Data("[]".utf8)))
        try state.enqueue(webSocketStateRequest(stream: "main", previous: "old"))
        #expect(try webSocketStateRejection(state.next()).code == "previous_response_not_found")
        try state.enqueue(webSocketStateRequest(stream: "main", previous: "new"))
        #expect(try webSocketStateTurn(&state).previousResponseID == "new")
    }

    @Test("Queued forks resolve lineage only when runnable")
    func queuedForkEviction() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxActiveResponses = 1
        var state = ResponsesWebSocketState(limits: limits)
        try webSocketStateSeed(&state, stream: "main", responseID: "parent", input: "parent")
        try state.enqueue(webSocketStateRequest(stream: "main", input: "advance", previous: "parent"))
        let advance = try webSocketStateTurn(&state)
        try state.enqueue(webSocketStateRequest(stream: "fork", previous: "parent"))
        #expect(state.next() == nil)
        try state.finish(advance, completion: .init(responseID: "advanced", output: Data("[]".utf8)))
        #expect(try webSocketStateRejection(state.next()).code == "previous_response_not_found")
    }

    @Test("A running fork retains its snapshot while the source lane advances")
    func frozenFork() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(
            &state,
            stream: "main",
            responseID: "parent",
            input: [["type": "reasoning", "encrypted_content": "provider-provenance"]])
        try state.enqueue(webSocketStateRequest(stream: "fork", input: "fork", previous: "parent"))
        let fork = try webSocketStateTurn(&state)
        try state.enqueue(webSocketStateRequest(stream: "main", input: "source", previous: "parent"))
        let source = try webSocketStateTurn(&state)
        try state.finish(source, completion: .init(responseID: "source", output: Data("[]".utf8)))
        try state.finish(fork, completion: .init(responseID: "fork", output: Data("[]".utf8)))
        try state.enqueue(webSocketStateRequest(stream: "fork", previous: "fork"))
        let continuation = try webSocketStateTurn(&state)
        let continuationInput = try webSocketStateInputData(continuation)
        #expect(try continuationInput == webSocketStateInputData(fork))
        #expect(String(data: continuationInput, encoding: .utf8)?.contains("provider-provenance") == true)
        #expect(String(data: continuationInput, encoding: .utf8)?.contains("source") == false)
    }

    @Test("A consumed compaction trigger replaces the cached history with the returned window")
    func compactionReplacement() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(&state, stream: "main", responseID: "parent", input: "superseded")
        try state.enqueue(
            webSocketStateRequest(stream: "main", input: [["type": "compaction_trigger"]], previous: "parent"))
        let compaction = try webSocketStateTurn(&state)
        #expect(compaction.replacesHistory)
        let compacted = Data(
            #"[{"type":"compaction","encrypted_content":"portable checkpoint","unknown":{"precise":1e400}}]"#.utf8)
        try state.finish(compaction, completion: .init(responseID: "compacted", output: compacted))
        try state.enqueue(webSocketStateRequest(stream: "main", previous: "compacted"))
        let continuation = try webSocketStateTurn(&state)
        #expect(try JSONValue.parse(webSocketStateInputData(continuation)) == JSONValue.parse(compacted))
    }

    @Test("Duplicate finish calls cannot publish old history or release a newer turn")
    func idempotentFinish() throws {
        var limits = ResponsesWebSocketLimits()
        limits.maxActiveResponses = 1
        var state = ResponsesWebSocketState(limits: limits)
        try state.enqueue(webSocketStateRequest(stream: "main"))
        let first = try webSocketStateTurn(&state)
        try state.finish(first, completion: .init(responseID: "first", output: Data("[]".utf8)))
        try state.enqueue(webSocketStateRequest(stream: "main", previous: "first"))
        let second = try webSocketStateTurn(&state)
        try state.enqueue(webSocketStateRequest(stream: "other"))
        try state.finish(first, completion: .init(responseID: "stale", output: Data("[]".utf8)))
        #expect(state.next() == nil)
        try state.finish(second, completion: nil)
        #expect(try webSocketStateTurn(&state).streamID == "other")
    }

    @Test("A duplicate provider response ID cannot silently mix two lane histories")
    func duplicateResponseIdentifier() throws {
        var state = ResponsesWebSocketState()
        try webSocketStateSeed(&state, stream: "first", responseID: "duplicate", input: "first")
        try webSocketStateSeed(&state, stream: "second", responseID: "second", input: "old second")
        try webSocketStateSeed(&state, stream: "second", responseID: "duplicate", input: "new second")
        for identifier in ["duplicate", "second"] {
            try state.enqueue(webSocketStateRequest(stream: "reader", previous: identifier))
            #expect(try webSocketStateRejection(state.next()).code == "previous_response_not_found")
        }
        try state.enqueue(webSocketStateRequest(stream: "first", input: "explicit replay"))
        #expect(try webSocketStateTurn(&state).previousResponseID == nil)
    }

    @Test("Replay preserves validated JSON bytes containing delimiters and exact numeric values")
    func replayPreservesEncodedItems() throws {
        let original = #"{"role":"user","content":"é ]},[ \"","native":{"number":1e400}}"#
        let output = #"{"type":"function_call","arguments":"{\"value\":\"]},[\"}","exact":9007199254740993}"#
        var state = ResponsesWebSocketState()
        try state.enqueue(
            Data("{\"type\":\"response.create\",\"model\":\"route\",\"input\":[\(original)]}".utf8))
        let first = try webSocketStateTurn(&state)
        let firstInput = try webSocketStateInputData(first)
        let canonicalInput = try #require(String(data: firstInput, encoding: .utf8))
        try state.finish(first, completion: .init(responseID: "parent", output: Data("[\(output)]".utf8)))
        try state.enqueue(webSocketStateRequest(previous: "parent"))
        let continuation = try webSocketStateTurn(&state)
        let expected = Data("\(canonicalInput.dropLast()),\(output)]".utf8)
        #expect(try webSocketStateInputData(continuation) == expected)
        #expect(try JSONValue.parse(continuation.body).object?["input"] == JSONValue.parse(expected))
    }
}
