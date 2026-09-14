import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

extension OpenAIResponsesTurnStreamingTests {
    @Test("Provider lifecycle rejects malformed, out-of-order, duplicate, and oversized events")
    func providerValidation() throws {
        var malformed = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try malformed.consume(
                ServerSentEventFrame(
                    event: "response.created",
                    data: Data("{".utf8),
                    terminal: false
                )
            )
        }

        var doneMarker = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try doneMarker.consume(
                ServerSentEventFrame(event: nil, data: Data(), terminal: true)
            )
        }

        var beforeStart = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try beforeStart.consume(
                responsesFrame(
                    "response.output_text.delta",
                    [
                        "output_index": 0,
                        "content_index": 0,
                        "item_id": "msg",
                        "delta": "early",
                    ]
                )
            )
        }

        var duplicateStart = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try duplicateStart.consume(createdFrame(id: "resp", createdAt: 1))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateStart.consume(createdFrame(id: "resp_other", createdAt: 2))
        }

        var missingItem = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try missingItem.consume(createdFrame(id: "resp", createdAt: 1))
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingItem.consume(
                responsesFrame(
                    "response.function_call_arguments.delta",
                    ["output_index": 0, "item_id": "fc", "delta": "{}"]
                )
            )
        }

        var unfinishedItem = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try unfinishedItem.consume(createdFrame(id: "resp", createdAt: 1))
        _ = try unfinishedItem.consume(
            responsesFrame(
                "response.output_item.added",
                [
                    "output_index": 0,
                    "item": functionCallItem(
                        id: "fc",
                        callID: "call",
                        name: "read",
                        arguments: "",
                        status: "in_progress"
                    ),
                ]
            )
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try unfinishedItem.consume(
                responsesFrame(
                    "response.completed",
                    [
                        "response": responseObject(
                            id: "resp",
                            createdAt: 1,
                            status: "completed",
                            output: [],
                            usage: .init(inputTokens: 0, outputTokens: 0)
                        )
                    ]
                )
            )
        }

        var missingTerminal = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try missingTerminal.consume(createdFrame(id: "resp", createdAt: 1))
        #expect(throws: OpenAIResponsesWebSearch.Error.streamEndedBeforeTerminal) {
            _ = try missingTerminal.finish()
        }
    }

    @Test("Provider terminal is unique and turn storage is bounded")
    func terminalAndBoundsValidation() throws {
        var failedResponse = responseObject(
            id: "resp_failed",
            createdAt: 1,
            status: "failed",
            output: [],
            usage: .init(inputTokens: 0, outputTokens: 0)
        )
        failedResponse["error"] = [
            "code": "server_error",
            "message": "provider failed",
        ]
        var duplicateTerminal = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try duplicateTerminal.consume(createdFrame(id: "resp_failed", createdAt: 1))
        _ = try duplicateTerminal.consume(
            responsesFrame("response.failed", ["response": failedResponse])
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateTerminal.consume(
                responsesFrame("response.failed", ["response": failedResponse])
            )
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try duplicateTerminal.finish()
        }

        var bounded = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 16)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try bounded.consume(createdFrame(id: "resp_far_too_large", createdAt: 1))
        }
    }

    @Test("Official failed terminal has no turn and becomes a safe public failure")
    func officialFailedTerminal() throws {
        let rawFailure: [String: Any] = [
            "id": "resp_failed_official",
            "object": "response",
            "status": "failed",
            "error": [
                "code": "provider_error",
                "message": "secret provider response body",
            ],
            "usage": NSNull(),
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(
            createdFrame(id: "resp_failed_official", createdAt: 90)
        )
        let normalized = try accumulator.consume(
            responsesFrame(
                "response.failed",
                ["sequence_number": 9_999, "response": rawFailure]
            )
        )
        let terminal = try #require(normalized.first)
        #expect(terminal.terminalStatus == .failed)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try accumulator.finish()
        }

        let prepared = try preparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        _ = try session.start(
            responseJSON: responseData(
                responseObject(
                    id: "resp_failed_official",
                    createdAt: 90,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )
        let frames = try session.consumePublic(terminal)
        let events = try publicEvents(frames)
        #expect(events.map(\.name) == ["error", "response.failed"])
        #expect(events.map(\.sequenceNumber) == [2, 3])
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("secret"))
        #expect(!stream.contains("provider_error"))
        let error = events[0].payload
        #expect(
            Set(error.keys)
                == ["type", "sequence_number", "code", "message", "param"]
        )
        let failed = try #require(events[1].payload["response"] as? [String: Any])
        #expect(
            failed["error"] as? [String: String]
                == [
                    "code": "server_error",
                    "message": "Internal server error",
                ]
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.fail(message: "again")
        }
    }

    @Test("Official context-length failure keeps only Codex's public error code")
    func officialContextLengthFailedTerminal() throws {
        let rawFailure: [String: Any] = [
            "id": "resp_failed_context",
            "object": "response",
            "status": "failed",
            "error": [
                "code": "context_length_exceeded",
                "message": "secret provider context details",
            ],
            "usage": NSNull(),
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(
            createdFrame(id: "resp_failed_context", createdAt: 92)
        )
        let terminal = try #require(
            try accumulator.consume(
                responsesFrame("response.failed", ["response": rawFailure])
            ).first
        )

        let prepared = try preparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        var frames = try session.start(
            responseJSON: responseData(
                responseObject(
                    id: "resp_failed_context",
                    createdAt: 92,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )
        frames += try session.consumePublic(terminal)

        let events = try publicEvents(frames)
        #expect(
            events.map(\.name)
                == ["response.created", "response.in_progress", "error", "response.failed"]
        )
        #expect(events.map(\.sequenceNumber) == Array(events.indices))
        #expect(events[2].payload["code"] as? String == "context_length_exceeded")
        #expect(events[2].payload["message"] as? String == "Internal server error")
        let failed = try #require(events[3].payload["response"] as? [String: Any])
        #expect(
            failed["error"] as? [String: String]
                == [
                    "code": "context_length_exceeded",
                    "message": "Internal server error",
                ]
        )
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("secret provider context details"))
    }

    @Test("Provider error events cannot pass through and use the safe failure path")
    func providerErrorIsPrivate() throws {
        let providerError: [String: Any] = [
            "type": "error",
            "sequence_number": 42,
            "code": "provider_secret_code",
            "message": "secret provider response body",
            "param": NSNull(),
        ]
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 4_096)
        _ = try accumulator.consume(createdFrame(id: "resp_error", createdAt: 91))
        #expect(
            try accumulator.consume(
                ServerSentEventFrame(
                    event: "untrusted-label",
                    data: responseData(providerError),
                    terminal: false
                )
            )
            .isEmpty
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.streamEndedBeforeTerminal) {
            _ = try accumulator.finish()
        }

        let prepared = try preparedWebSearchRequest()
        var session = ResponsesPublicStreamSession(webSearch: prepared)
        _ = try session.start(
            responseJSON: responseData(
                responseObject(
                    id: "resp_error",
                    createdAt: 91,
                    status: "in_progress",
                    output: [],
                    usage: nil
                )
            )
        )
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.consumePublic(
                .passthrough(type: "error", payloadJSON: responseData(providerError))
            )
        }
        let frames = try session.fail(message: "secret provider response body")
        let events = try publicEvents(frames)
        #expect(events.map(\.name) == ["error", "response.failed"])
        let stream = try #require(String(bytes: frames.joined(), encoding: .utf8))
        #expect(!stream.contains("secret"))
        #expect(!stream.contains("provider_secret_code"))
    }
}
