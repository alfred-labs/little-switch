import Foundation
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTConversationStreamBoundaryTests {
    @Test(arguments: ["error", "incomplete_details"])
    func completedStatusCannotHideFailureMetadata(field: String) throws {
        for value in ["null", #"{"reason":"failure"}"#] {
            var stream = Self.stream()
            let frame =
                "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[],\"\(field)\":\(value)}}\n\n"
            if value == "null" {
                #expect(try !stream.append(ByteBuffer(string: frame)).isEmpty)
                #expect(stream.completed)
                #expect(try stream.finish().isEmpty)
            } else {
                #expect(throws: ChatGPTConversationError.providerFailed) {
                    try stream.append(ByteBuffer(string: frame))
                }
                #expect(!stream.completed)
                #expect(throws: ChatGPTConversationError.providerFailed) { try stream.finish() }
            }
        }
    }

    @Test(arguments: ["x", ""])
    func manySmallFramesEmitAtMostOneProgressSnapshot(delta: String) throws {
        var stream = Self.stream()
        let initialText = String(repeating: "a", count: 16 * 1_024)
        _ = try stream.append(
            ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"\(initialText)\"}\n\n"))
        let frame = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"\(delta)\"}\n\n"
        let output = try stream.append(ByteBuffer(string: String(repeating: frame, count: 64)))
        #expect(stream.text == initialText + String(repeating: delta, count: 64))
        #expect(output.count < 20 * 1_024)
        let rendered = try #require(String(data: output, encoding: .utf8))
        let emitted = rendered.components(separatedBy: "data: ").count - 1
        #expect(emitted <= 1)
        if !delta.isEmpty {
            #expect(emitted == 1)
        }
    }

    @Test(arguments: [
        "[]",
        #"[{"type":"reasoning","summary":[]}]"#,
        #"[{"type":"message","role":"assistant","content":[]}]"#,
    ])
    func explicitlyEmptyCompletedOutputRejectsPriorText(output: String) throws {
        var stream = Self.stream()
        _ = try stream.append(
            ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"))
        let terminal =
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":\(output)}}\n\n"
        #expect(throws: ChatGPTConversationError.inconsistentOutput) { try stream.append(ByteBuffer(string: terminal)) }
        #expect(!stream.completed)
        #expect(throws: ChatGPTConversationError.inconsistentOutput) { try stream.finish() }
    }

    @Test func completedTextMustMatchTheExactUnicodeBytes() throws {
        var stream = Self.stream()
        _ = try stream.append(ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"é\"}\n\n"))
        let terminal =
            #"data: {"type":"response.completed","response":{"status":"completed","output":["#
            + #"{"type":"message","role":"assistant","content":[{"type":"output_text","text":"é"}]}]}}"#
            + "\n\n"
        #expect(throws: ChatGPTConversationError.inconsistentOutput) {
            try stream.append(ByteBuffer(string: terminal))
        }
    }

    @Test func textAnnotationsAreIgnoredWithoutLeakingMetadata() throws {
        var stream = Self.stream()
        let output = try stream.append(
            ByteBuffer(
                string: #"""
                    data: {"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://private.invalid","title":"private"}}


                    """#))
        #expect(output.isEmpty)
    }

    @Test(arguments: [
        #"{"type":"response.output_text.delta","delta":false}"#,
        #"{"type":"response.completed"}"#,
        #"{"type":"response.completed","response":{"status":"completed"}}"#,
        #"{"type":"response.completed","response":{"status":"completed","output":{}}}"#,
        #"{"type":"response.completed","response":{"status":"completed","output":[{}]}}"#,
        #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":{}}]}}"#,
        #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":false}]}]}}"#,
        #"{"type":"response.created"}"#,
        #"{"type":"response.output_item.done"}"#,
        #"{"type":"response.content_part.done"}"#,
        #"{"type":"response.output_text.done","text":false}"#,
    ])
    func malformedLifecyclePayloadsFailClosed(json: String) {
        var stream = Self.stream()
        #expect(throws: ChatGPTConversationError.invalidStream) {
            try stream.append(ByteBuffer(string: "data: \(json)\n\n"))
        }
        #expect(throws: ChatGPTConversationError.invalidStream) {
            try stream.append(ByteBuffer(string: "data: [DONE]\n\n"))
        }
    }

    @Test func terminalFailuresAndMalformedFramesCannotBecomeSuccess() throws {
        var failed = Self.stream()
        #expect(throws: ChatGPTConversationError.providerFailed) {
            try failed.append(
                ByteBuffer(
                    string:
                        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"incomplete\",\"output\":[]}}\n\n"
                ))
        }
        var truncated = Self.stream()
        _ = try truncated.append(ByteBuffer(string: "data: {\"type\":\"response.completed\"}"))
        #expect(throws: ChatGPTConversationError.invalidStream) { try truncated.finish() }
        var mismatched = Self.stream()
        #expect(throws: ChatGPTConversationError.invalidStream) {
            try mismatched.append(
                ByteBuffer(
                    string:
                        "event: response.failed\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"x\"}\n\n"))
        }
    }

    @Test func finishFlushesDeferredCRAndAcceptsEmptyCompletedOutput() throws {
        var stream = Self.stream()
        let result = try stream.append(
            ByteBuffer(
                string:
                    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}\r\r")
        )
        #expect(result.isEmpty)
        #expect(try !stream.finish().isEmpty)
        #expect(stream.completed)
        #expect(stream.text.isEmpty)
        #expect(throws: ChatGPTConversationError.invalidStream) {
            try stream.append(
                ByteBuffer(string: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"late\"}\n\n"))
        }
        #expect(!stream.completed)
    }

    private static func stream() -> ChatGPTConversationStream {
        ChatGPTConversationStream(
            conversationID: "1e1771e5-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            message: .init(
                id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", parentID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
            model: "vendor:model",
            timestamp: 123)
    }
}
