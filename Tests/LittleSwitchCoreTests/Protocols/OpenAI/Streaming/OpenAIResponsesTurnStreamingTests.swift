import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses turn streaming")
struct OpenAIResponsesTurnStreamingTests {
    @Test("Native events publish immediately and reconstruct the terminal response")
    func completedTurnReconstruction() throws {
        let frames = try completedProviderFrames()

        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 64 * 1_024)
        var events: [ResponsesProviderStreamEvent] = []
        for frame in frames {
            events += try accumulator.consume(frame)
        }

        let turn = try accumulator.finish()
        #expect(turn.id == "resp_provider")
        #expect(turn.usage == ResponsesUsage(inputTokens: 12, outputTokens: 7))
        #expect(
            turn.webSearchCall
                == ResponsesWebSearchToolCall(callID: "call_search", query: "latest Swift")
        )
        #expect(events.contains { $0.outputTextDelta == "FIRST" })
        #expect(
            events.contains {
                $0.functionDelta
                    == FunctionEventFixture(
                        itemID: "fc_private",
                        callID: "call_search",
                        name: "web_search",
                        value: #"{"query":"latest "#
                    )
            }
        )
        #expect(
            events.contains {
                $0.functionDone
                    == FunctionEventFixture(
                        itemID: "fc_private",
                        callID: "call_search",
                        name: "web_search",
                        value: #"{"query":"latest Swift"}"#
                    )
            }
        )
        #expect(events.contains { $0.passthroughType == "response.in_progress" })
        #expect(events.contains { $0.passthroughType == "response.content_part.done" })
        #expect(events.last?.terminalStatus == .completed)
    }

    @Test("Incomplete ordinary calls retain normalized names and call IDs")
    func incompleteOrdinaryFunction() throws {
        let pending = functionCallItem(
            id: "fc_read",
            callID: "call_read",
            name: "read_file",
            arguments: "",
            status: "in_progress"
        )
        let completed = functionCallItem(
            id: "fc_read",
            callID: "call_read",
            name: "read_file",
            arguments: #"{"path":"README.md"}"#,
            status: "completed"
        )
        let terminal = responseObject(
            id: "resp_incomplete",
            createdAt: 50,
            status: "incomplete",
            output: [completed],
            usage: ResponsesUsage(inputTokens: 3, outputTokens: 4)
        )
        let frames = try [
            createdFrame(id: "resp_incomplete", createdAt: 50),
            responsesFrame(
                "response.output_item.added",
                ["output_index": 8, "item": pending]
            ),
            responsesFrame(
                "response.function_call_arguments.delta",
                [
                    "output_index": 8,
                    "item_id": "fc_read",
                    "delta": #"{"path":"README"#,
                ]
            ),
            responsesFrame(
                "response.function_call_arguments.done",
                [
                    "output_index": 8,
                    "item_id": "fc_read",
                    "call_id": "call_read",
                    "name": "read_file",
                    "arguments": #"{"path":"README.md"}"#,
                ]
            ),
            responsesFrame(
                "response.output_item.done",
                ["output_index": 8, "item": completed]
            ),
            responsesFrame("response.incomplete", ["response": terminal]),
        ]

        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 32 * 1_024)
        let events = try frames.flatMap { try accumulator.consume($0) }
        let turn = try accumulator.finish()

        #expect(turn.id == "resp_incomplete")
        #expect(turn.webSearchCall == nil)
        #expect(events.last?.terminalStatus == .incomplete)
        #expect(
            events.contains {
                $0.functionDone
                    == FunctionEventFixture(
                        itemID: "fc_read",
                        callID: "call_read",
                        name: "read_file",
                        value: #"{"path":"README.md"}"#
                    )
            }
        )
    }

    @Test("Body ending mid-stream fails as streamEndedBeforeTerminal")
    func truncatedStreamFailsWithDedicatedError() throws {
        let messageStart: [String: Any] = [
            "id": "msg_truncated",
            "type": "message",
            "status": "in_progress",
            "role": "assistant",
            "content": [],
        ]
        let frames = try [
            createdFrame(id: "resp_truncated", createdAt: 10),
            responsesFrame(
                "response.output_item.added",
                ["output_index": 0, "item": messageStart]
            ),
        ]

        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 64 * 1_024)
        for frame in frames {
            _ = try accumulator.consume(frame)
        }

        #expect(throws: OpenAIResponsesWebSearch.Error.streamEndedBeforeTerminal) {
            try accumulator.finish()
        }
    }

    @Test("Body ending before any event fails as streamEndedBeforeTerminal")
    func emptyStreamFailsWithDedicatedError() {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 64 * 1_024)

        #expect(throws: OpenAIResponsesWebSearch.Error.streamEndedBeforeTerminal) {
            try accumulator.finish()
        }
    }

    @Test("Finishing twice after success fails as invalidResponse")
    func doubleFinishAfterSuccessFails() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 64 * 1_024)
        for frame in try completedProviderFrames() {
            _ = try accumulator.consume(frame)
        }
        _ = try accumulator.finish()

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.finish()
        }
    }
}

extension OpenAIResponsesTurnStreamingTests {
    /// Replays the exact five SSE events of a recorded failed native vLLM
    /// burst (medium, /v1/responses, died as invalidProviderStream). If this
    /// parses without throwing, the native failures are a real server-side
    /// termination, not a parser rejection — unlike the SGLang null-delta bug.
    @Test("Recorded native vLLM burst frames parse without rejection")
    func recordedNativeBurstFramesParse() throws {
        let reasoningItem: [String: Any] = [
            "id": "b501b9c4c76c35c2",
            "summary": [],
            "type": "reasoning",
            "content": NSNull(),
            "encrypted_content": NSNull(),
            "status": "in_progress",
        ]
        let frames = try [
            createdFrame(id: "resp_8ec519d28d95997a", createdAt: 1_788_506_972),
            responsesFrame("response.in_progress", [String: Any]()),
            responsesFrame(
                "response.output_item.added",
                ["output_index": 0, "item": reasoningItem]
            ),
            responsesFrame(
                "response.reasoning_part.added",
                [
                    "content_index": 0,
                    "item_id": "b501b9c4c76c35c2",
                    "output_index": 0,
                    "part": ["text": "", "type": "reasoning_text"],
                ]
            ),
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "content_index": 0,
                    "delta": "The user",
                    "item_id": "b501b9c4c76c35c2",
                    "output_index": 0,
                ]
            ),
        ]

        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4 * 1_024 * 1_024)
        for frame in frames {
            _ = try accumulator.consume(frame)
        }
        // The stream ends here in the recording — that end is the finding,
        // not an error. This expectation documents the diagnosis: consuming
        // every recorded frame must not throw.
        #expect(throws: Never.self) {}
    }
}

extension OpenAIResponsesTurnStreamingTests {
    /// Replays a fresh failed native burst frame-for-frame (medium,
    /// /v1/responses, invalidProviderStream after the third reasoning delta).
    @Test("Recorded native burst with three reasoning deltas parses")
    func recordedNativeThreeDeltasParse() throws {
        let reasoningItem: [String: Any] = [
            "id": "83a009f8dee2cc6d",
            "summary": [],
            "type": "reasoning",
            "content": NSNull(),
            "encrypted_content": NSNull(),
            "status": "in_progress",
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4 * 1_024 * 1_024)
        let frames = try [
            createdFrame(id: "resp_8e7127ad45508938", createdAt: 1_788_523_676),
            responsesFrame("response.in_progress", [String: Any]()),
            responsesFrame(
                "response.output_item.added",
                ["output_index": 0, "item": reasoningItem]
            ),
            responsesFrame(
                "response.reasoning_part.added",
                [
                    "content_index": 0,
                    "item_id": "83a009f8dee2cc6d",
                    "output_index": 0,
                    "part": ["text": "", "type": "reasoning_text"],
                ]
            ),
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "content_index": 0, "delta": "The user",
                    "item_id": "83a009f8dee2cc6d", "output_index": 0,
                ]
            ),
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "content_index": 0, "delta": " is",
                    "item_id": "83a009f8dee2cc6d", "output_index": 0,
                ]
            ),
            responsesFrame(
                "response.reasoning_text.delta",
                [
                    "content_index": 0, "delta": " saying \"",
                    "item_id": "83a009f8dee2cc6d", "output_index": 0,
                ]
            ),
        ]
        for frame in frames {
            _ = try accumulator.consume(frame)
        }
    }
}

extension OpenAIResponsesTurnStreamingTests {
    /// vLLM's function_call items and argument deltas carry explicit nulls
    /// (caller, namespace, call_id, name). A null means the field is absent
    /// — captured from a live medium burst that died on exactly this item.
    @Test("vLLM function_call nulls parse as absent")
    func vllmFunctionCallNullsParseAsAbsent() throws {
        let functionItem: [String: Any] = [
            "arguments": "",
            "call_id": "call_a9008abf11c95fe9",
            "name": "exec_command",
            "type": "function_call",
            "id": "823828db2daa0e1c",
            "caller": NSNull(),
            "namespace": NSNull(),
            "status": "in_progress",
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4 * 1_024 * 1_024)
        let frames = try [
            createdFrame(id: "resp_5369b747", createdAt: 1),
            responsesFrame("response.in_progress", [String: Any]()),
            responsesFrame(
                "response.output_item.added",
                ["output_index": 1, "item": functionItem]
            ),
            responsesFrame(
                "response.function_call_arguments.delta",
                [
                    "output_index": 1,
                    "item_id": "823828db2daa0e1c",
                    "delta": #"{"command""#,
                    "call_id": NSNull(),
                    "name": NSNull(),
                ]
            ),
        ]
        for frame in frames {
            _ = try accumulator.consume(frame)
        }
    }
}
