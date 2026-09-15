import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom SSE frame editing boundaries")
struct CustomToolFrameRewriteTests {
    @Test("Suppressing a retained argument delta keeps transport metadata", arguments: ["\n", "\r\n", "\r"])
    func suppressRetainsMetadata(lineEnding: String) throws {
        let lines = [
            ": data: retained comment", "id: 17", "retry: 500", "x-event: retained", "event", "data",
            "event: response.function_call_arguments.delta", "data: {}", "", "",
        ]
        let source = Data(lines.joined(separator: lineEnding).utf8)
        let frame = try #require(decode(source).first)
        let result = try CustomToolFrameRewrite.apply(.suppress, frame: frame, source: source, offset: 0)
        let expected = [": data: retained comment", "id: 17", "retry: 500", "x-event: retained", "", ""]
        #expect(result == Data(expected.joined(separator: lineEnding).utf8))
        #expect(try decode(result).isEmpty)
    }

    @Test("Custom input completion changes only the data and event fields", arguments: ["\n", "\r\n", "\r"])
    func completionRetainsMetadata(lineEnding: String) throws {
        let prefix = Data(": earlier comment\n\n".utf8)
        let source = Data(
            [
                ": retain", "id: 17", "event: response.function_call_arguments.done", "retry: 500", "data: {}", "", "",
            ].joined(separator: lineEnding).utf8)
        let frame = try #require(decode(prefix + source).first)
        let payload = #"{"type":"response.custom_tool_call_input.done","input":"line\nnext"}"#
        let result = try CustomToolFrameRewrite.apply(
            .replace(JSONValue.parse(Data(payload.utf8))), frame: frame, source: source, offset: prefix.count)
        let expected = [
            ": retain", "id: 17", "event: response.custom_tool_call_input.done", "retry: 500", "data: " + payload, "",
            "",
        ]
        #expect(result == Data(expected.joined(separator: lineEnding).utf8))
        #expect(try decode(result).first?.event == "response.custom_tool_call_input.done")
    }

    @Test("Data rewrites neither manufacture event labels nor change unrelated labels")
    func unchangedEventLabel() throws {
        let fixtures: [(String, String)] = [
            ("", #"{"type":"response.custom_tool_call_input.done","input":"x"}"#),
            (
                "event: response.custom_tool_call_input.done\n",
                #"{"type":"response.custom_tool_call_input.done","input":"x"}"#
            ),
            ("event: provider.chunk\n", #"{"choices":[]}"#),
        ]
        for (event, payload) in fixtures {
            let source = Data((event + "data: {}\n\n").utf8)
            let frame = try #require(decode(source).first)
            let result = try CustomToolFrameRewrite.apply(
                .replace(JSONValue.parse(Data(payload.utf8))), frame: frame, source: source, offset: 0)
            #expect(result == Data((event + "data: " + payload + "\n\n").utf8))
        }
    }

    @Test("Keeping a frame preserves bytes without requiring rewrite provenance")
    func keepWithoutSourceMetadata() throws {
        let source = Data("event: ordinary\rdata: {}\r\r".utf8)
        let frame = ServerSentEventFrame(event: "ordinary", data: Data("{}".utf8), terminal: false)
        #expect(try CustomToolFrameRewrite.apply(.keep, frame: frame, source: source, offset: 93) == source)
    }

    @Test("Suppression handles a final source line without a line ending")
    func suppressUnterminatedLine() throws {
        let frame = ServerSentEventFrame(event: nil, data: Data("{}".utf8), terminal: false)
        let fixtures = [
            ("event: arguments.delta\ndata: {}", ""),
            ("data: {}\nid: retained", "id: retained"),
        ]
        for (source, expected) in fixtures {
            #expect(
                try CustomToolFrameRewrite.apply(
                    .suppress, frame: frame, source: Data(source.utf8), offset: 0) == Data(expected.utf8))
        }
    }

    private func decode(_ source: Data) throws -> [ServerSentEventFrame] {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4_096)
        return try decoder.append(ByteBuffer(bytes: source)) + decoder.finish()
    }
}
