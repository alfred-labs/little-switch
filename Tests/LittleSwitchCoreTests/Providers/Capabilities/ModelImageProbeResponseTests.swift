import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image probe response classification")
struct ModelImageProbeResponseTests {
    @Test(
        "Only completed final visual answers verify the challenge",
        arguments: [ModelImageInputWire.responses, .chatCompletions])
    func semanticVerification(wire: ModelImageInputWire) {
        #expect(classify(ModelImageProbeFixture.answer(wire: wire), wire: wire) == .verified)
        #expect(
            classify(ModelImageProbeFixture.answer(wire: wire, text: "red red red red"), wire: wire)
                == .inconclusive(.wrongAnswer))
        #expect(
            classify(ModelImageProbeFixture.answer(wire: wire, text: "white white yellow black extra"), wire: wire)
                == .inconclusive(.wrongAnswer))
        #expect(
            classify(ModelImageProbeFixture.answer(wire: wire, text: "WHITE, WHITE, YELLOW, BLACK"), wire: wire)
                == .verified)
        #expect(
            classify(ModelImageProbeFixture.answer(wire: wire, completed: false), wire: wire)
                == .inconclusive(.incompleteResponse))
        #expect(classify(Data("{}".utf8), wire: wire) == .inconclusive(.invalidResponse))
        #expect(classify(Data("not JSON".utf8), wire: wire) == .inconclusive(.invalidResponse))
        #expect(classify(Data(repeating: 32, count: 32 * 1_024 + 1), wire: wire) == .inconclusive(.sizeLimit))
    }

    @Test("Exact image rejection differs from generic validation, auth and quota errors")
    func strictRejection() {
        let error = Data(
            #"{"error":{"code":"1210","message":"messages.content.type is invalid, allowed values: ['text']"}}"#.utf8)
        #expect(classify(error, status: 400, wire: .chatCompletions) == .unsupported)
        #expect(!ModelImageInputRejection.matches(status: 400, body: error, hasImageInput: false))
        for status in [401, 403, 429, 500] {
            #expect(classify(error, status: status, wire: .chatCompletions) == .inconclusive(.httpStatus(status)))
        }
        for status in [404, 405] {
            #expect(classify(error, status: status, wire: .responses) == .inconclusive(.routeUnavailable))
        }
        for body in [
            #"{"error":{"code":"1210"}}"#, #"{"error":{"message":"Invalid tool schema"}}"#,
            #"{"error":{"message":"Unsupported image encoding"}}"#,
        ] {
            #expect(!ModelImageInputRejection.matches(status: 400, body: Data(body.utf8), hasImageInput: true))
        }
        #expect(
            ModelImageInputRejection.matches(
                status: 400,
                body: Data(#"{"error":{"message":"This model does not support image input."}}"#.utf8),
                hasImageInput: true))
    }

    @Test("SSE requires a complete terminal and ignores reasoning text")
    func eventStreams() throws {
        let answer = try #require(String(data: ModelImageProbeFixture.answer(wire: .responses), encoding: .utf8))
            .replacingOccurrences(of: "\n", with: "")
        let native = "event: response.completed\ndata: \(answer)\n\n"
        #expect(classify(Data(native.utf8), wire: .responses) == .verified)
        let chat =
            #"data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"white white yellow black","reasoning_content":"red red red red"},"finish_reason":"stop"}]}"#
            + "\n\ndata: [DONE]\n\n"
        #expect(classify(Data(chat.utf8), wire: .chatCompletions) == .verified)
        let unfinished =
            #"data: {"choices":[{"index":0,"delta":{"content":"white white yellow black"},"finish_reason":null}]}"#
            + "\n\n"
        #expect(classify(Data(unfinished.utf8), wire: .chatCompletions) == .inconclusive(.incompleteResponse))
        #expect(
            classify(Data("event: response.completed\ndata: {".utf8), wire: .responses)
                == .inconclusive(.incompleteResponse))
    }

    @Test("Errors and content after the terminal cannot verify a stream")
    func conflictingStream() throws {
        let answer = try #require(String(data: ModelImageProbeFixture.answer(wire: .responses), encoding: .utf8))
            .replacingOccurrences(of: "\n", with: "")
        let completed = "event: response.completed\ndata: \(answer)\n\n"
        let error = "event: error\ndata: {\"error\":{\"message\":\"failure\"}}\n\n"
        #expect(classify(Data((error + completed).utf8), wire: .responses) == .inconclusive(.invalidResponse))
        let chat =
            #"data: {"choices":[{"delta":{"content":"white white yellow black"},"finish_reason":"stop"}]}"#
            + "\n\ndata: [DONE]\n\n"
        #expect(classify(Data((chat + chat).utf8), wire: .chatCompletions) == .inconclusive(.invalidResponse))
    }

    @Test("Missing usage is unknown, not zero, and declared usage stays available on a wrong answer")
    func usage() {
        #expect(
            ModelImageProbeResponse.usage(body: ModelImageProbeFixture.answer(wire: .responses), wire: .responses)
                == nil)
        let body = Data(#"{"usage":{"input_tokens":187,"output_tokens":63,"total_tokens":250}}"#.utf8)
        #expect(
            ModelImageProbeResponse.usage(body: body, wire: .responses)
                == ResponsesUsage(inputTokens: 187, outputTokens: 63))
        let chat = Data(
            #"{"usage":{"prompt_tokens":187,"completion_tokens":63,"completion_tokens_details":{"reasoning_tokens":50}}}"#
                .utf8)
        #expect(
            ModelImageProbeResponse.usage(body: chat, wire: .chatCompletions)
                == ResponsesUsage(inputTokens: 187, outputTokens: 63, reasoningOutputTokens: 50))
        #expect(ModelImageProbeResponse.usage(body: Data(#"{"usage":{}}"#.utf8), wire: .responses) == nil)
    }

    @Test(
        "An error on a successful HTTP response cannot verify the challenge",
        arguments: [ModelImageInputWire.responses, .chatCompletions])
    func contradictoryJSON(wire: ModelImageInputWire) throws {
        var root = try WireJSONCompatibility.fields(ModelImageProbeFixture.answer(wire: wire))
        root["error"] = ["message": "synthetic failure"]
        #expect(classify(try WireJSONCompatibility.data(root), wire: wire) == .inconclusive(.invalidResponse))
        root["error"] = NSNull()
        #expect(classify(try WireJSONCompatibility.data(root), wire: wire) == .verified)
    }

    @Test("Responses stream terminal identity and its completed payload must agree")
    func contradictoryResponsesTerminal() throws {
        let answer = try #require(String(data: ModelImageProbeFixture.answer(wire: .responses), encoding: .utf8))
            .replacingOccurrences(of: "\n", with: "")
        for event in ["response.failed", "response.incomplete"] {
            let stream = "event: \(event)\ndata: {\"response\":\(answer)}\n\n"
            #expect(classify(Data(stream.utf8), wire: .responses) == .inconclusive(.invalidResponse))
        }
        let completed = "event: response.completed\ndata: {\"response\":\(answer)}\n\n"
        let delta = "event: response.output_text.delta\ndata: {\"delta\":\"red\"}\n\n"
        #expect(classify(Data((completed + delta).utf8), wire: .responses) == .inconclusive(.invalidResponse))
        #expect(classify(Data((completed + "data: [DONE]\n\n").utf8), wire: .responses) == .verified)
    }

    private func classify(_ body: Data, status: Int = 200, wire: ModelImageInputWire) -> ModelImageInputProbeOutcome {
        ModelImageProbeResponse.classify(
            body: body, status: status, wire: wire, expectedColors: ModelImageProbeFixture.colors)
    }
}

enum ModelImageProbeFixture {
    static let colors = ["white", "white", "yellow", "black"]

    static func answer(
        wire: ModelImageInputWire,
        text: String = "white white yellow black",
        completed: Bool = true
    ) -> Data {
        if wire == .responses {
            return Data(
                """
                {"status":"\(completed ? "completed" : "incomplete")","output":[
                {"type":"message","role":"assistant","content":[{"type":"output_text","text":"\(text)"}]}]}
                """.utf8)
        }
        return Data(
            """
            {"choices":[{"index":0,"finish_reason":"\(completed ? "stop" : "length")",
            "message":{"role":"assistant","content":"\(text)","reasoning_content":"red red red red"}}]}
            """.utf8)
    }
}
