import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTConversationStreamTests {
    @Test func splitUTF8AndCRLFFromProviderBecomeFullNativeSnapshots() throws {
        var stream = Self.stream()
        let source = Data(
            ("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Bonjour 🐈\"}\r\n\r\n"
                + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"!\"}\r\n\r\n"
                + Self.completed("Bonjour 🐈!") + "data: [DONE]\n\n").utf8)
        var output = Data()
        for byte in source {
            output.append(try stream.append(ByteBuffer(bytes: [byte])))
        }
        output.append(try stream.finish())
        #expect(stream.completed)
        #expect(stream.text == "Bonjour 🐈!")
        let frames = try Self.frames(output)
        #expect(frames.count == 5)
        #expect(frames.last?.terminal == true)
        let objects = try frames.dropLast().map {
            try #require(JSONSerialization.jsonObject(with: $0.data) as? [String: Any])
        }
        let texts = objects.prefix(3).map {
            (($0["message"] as? [String: Any])?["content"] as? [String: Any])?["parts"] as? [String]
        }
        #expect(texts == [["Bonjour 🐈"], ["Bonjour 🐈!"], ["Bonjour 🐈!"]])
        let final = try #require(objects[2]["message"] as? [String: Any])
        let expected = Data(
            #"""
            {"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","author":{"role":"assistant","name":null,"metadata":{}},
             "create_time":123,"update_time":123,"content":{"content_type":"text","parts":["Bonjour 🐈!"]},
             "status":"finished_successfully","end_turn":true,"weight":1,"recipient":"all","channel":"final",
             "metadata":{"model_slug":"vendor:model","parent_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
               "finish_details":{"type":"stop","stop_tokens":[]}}}
            """#.utf8)
        #expect(try final as NSDictionary == JSONSerialization.jsonObject(with: expected) as? NSDictionary)
        #expect(
            objects[3] as NSDictionary == ["type": "message_stream_complete", "conversation_id": Self.conversationID]
                as NSDictionary)
        #expect(objects.prefix(3).allSatisfy { $0["conversation_id"] as? String == Self.conversationID })
    }

    @Test func completedOutputWithoutDeltasAndOptionalTitle() throws {
        var stream = Self.stream(title: "Synthetic title")
        let output = try stream.append(ByteBuffer(string: Self.completed("answer")))
        #expect(try stream.finish().isEmpty)
        #expect(stream.text == "answer")
        let frames = try Self.frames(output)
        #expect(frames.count == 4)
        let title = try #require(JSONSerialization.jsonObject(with: frames[1].data) as? NSDictionary)
        #expect(
            title == ["type": "title_generation", "conversation_id": Self.conversationID, "title": "Synthetic title"]
                as NSDictionary)
    }

    @Test(arguments: [
        #"{"type":"response.failed","response":{"error":{"message":"private provider payload"}}}"#,
        #"{"type":"response.incomplete","response":{"status":"incomplete"}}"#,
        #"{"type":"error","message":"private provider payload"}"#,
    ])
    func providerFailuresNeverFinishSuccessfully(json: String) throws {
        var stream = Self.stream()
        _ = try stream.append(
            ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"))
        #expect(throws: ChatGPTConversationError.providerFailed) {
            try stream.append(ByteBuffer(string: "data: \(json)\n\n"))
        }
        #expect(!stream.completed)
        #expect(throws: ChatGPTConversationError.providerFailed) { try stream.finish() }
    }

    @Test(arguments: [
        #"{"type":"response.output_item.added","item":{"type":"function_call","name":"private"}}"#,
        #"{"type":"response.function_call_arguments.delta","delta":"private"}"#,
        #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"web_search_call"}]}}"#,
        #"{"type":"response.content_part.added","part":{"type":"refusal","refusal":"private"}}"#,
    ])
    func rejectsToolAndNonTextOutput(json: String) {
        var stream = Self.stream()
        #expect(throws: ChatGPTConversationError.unsupportedOutput) {
            try stream.append(ByteBuffer(string: "data: \(json)\n\n"))
        }
        #expect(!stream.completed)
    }

    @Test func rejectsInconsistentCompletedTextAndMissingTerminal() throws {
        var stream = Self.stream()
        _ = try stream.append(
            ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"))
        #expect(throws: ChatGPTConversationError.inconsistentOutput) {
            try stream.append(ByteBuffer(string: Self.completed("different")))
        }
        #expect(!stream.completed)
        var incomplete = Self.stream()
        #expect(throws: ChatGPTConversationError.missingCompletion) { try incomplete.finish() }
        var prematureDone = Self.stream()
        #expect(throws: ChatGPTConversationError.missingCompletion) {
            try prematureDone.append(ByteBuffer(string: "data: [DONE]\n\n"))
        }
    }

    @Test(arguments: ["data: not-json\n\n", "data: []\n\n", "data: {\"delta\":\"private\"}\n\n"])
    func rejectsMalformedFrames(source: String) {
        var stream = Self.stream()
        #expect(throws: ChatGPTConversationError.invalidStream) { try stream.append(ByteBuffer(string: source)) }
    }

    @Test func enforcesFrameAndTextLimitsAndUTF8() throws {
        var oversized = Self.stream()
        #expect(throws: ChatGPTConversationError.limitExceeded) {
            try oversized.append(ByteBuffer(bytes: [UInt8](repeating: 0x61, count: 8 * 1_024 * 1_024 + 1)))
        }
        var largeText = Self.stream()
        let json = try JSONSerialization.data(withJSONObject: [
            "type": "response.output_text.delta", "delta": String(repeating: "a", count: 4 * 1_024 * 1_024 + 1),
        ])
        var frame = Data("data: ".utf8)
        frame.append(json)
        frame.append(Data("\n\n".utf8))
        #expect(throws: ChatGPTConversationError.limitExceeded) { try largeText.append(ByteBuffer(bytes: frame)) }
        var invalid = Self.stream()
        #expect(throws: ChatGPTConversationError.invalidStream) {
            try invalid.append(ByteBuffer(bytes: [0xFF, 0x0A, 0x0A]))
        }
    }

    @Test func lifecycleAndReasoningAreIgnoredWithoutLeakingPayloads() throws {
        var stream = Self.stream()
        let output = try stream.append(
            ByteBuffer(
                string: #"""
                    data: {"type":"response.created","response":{"status":"in_progress","output":[]}}

                    data: {"type":"response.reasoning_summary_text.delta","delta":"private reasoning"}

                    data: {"type":"response.output_item.added","item":{"type":"reasoning","summary":[]}}


                    """#))
        #expect(output.isEmpty)
    }

    private static let conversationID = "1e1771e5-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    private static func stream(title: String? = nil) -> ChatGPTConversationStream {
        ChatGPTConversationStream(
            conversationID: conversationID,
            message: .init(
                id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", parentID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
            model: "vendor:model",
            timestamp: 123,
            title: title
        )
    }

    private static func completed(_ text: String) -> String {
        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":["
            + "{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(text)\"}]}]}}\n\n"
    }

    private static func frames(_ data: Data) throws -> [ServerSentEventFrame] {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 8 * 1_024 * 1_024)
        return try decoder.append(ByteBuffer(bytes: data)) + decoder.finish()
    }
}
