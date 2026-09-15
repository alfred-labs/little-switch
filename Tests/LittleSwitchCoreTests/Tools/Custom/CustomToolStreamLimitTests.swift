import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom stream call bounds")
struct CustomToolStreamLimitTests {
    @Test("The 129th retained call fails without truncation", arguments: [false, true])
    func callLimit(chat: Bool) throws {
        let body = Data(
            (chat
                ? #"{"tools":[{"type":"custom","custom":{"name":"exec"}}]}"#
                : #"{"tools":[{"type":"custom","name":"exec"}]}"#).utf8)
        let projection = try CustomToolProjection.prepare(
            body: body, wire: chat ? .chatCompletions : .responses, adapt: true)
        var state = CustomToolStreamProjection(projection: projection, maximumBytes: 65_536)
        for index in 0..<128 { _ = try state.consume(frame(index: index, chat: chat)) }
        #expect(throws: CustomToolProjection.Error.limitExceeded) {
            try state.consume(frame(index: 128, chat: chat))
        }
    }

    private func frame(index: Int, chat: Bool) throws -> ServerSentEventFrame {
        let value: JSONValue
        if chat {
            value = .object([
                "choices": .array([
                    .object([
                        "index": .integer(0),
                        "delta": .object([
                            "tool_calls": .array([
                                .object([
                                    "index": .integer(index), "id": .string("call\(index)"),
                                    "type": .string("function"),
                                    "function": .object(["name": .string("exec"), "arguments": .string("")]),
                                ])
                            ])
                        ]),
                    ])
                ])
            ])
        } else {
            value = .object([
                "type": .string("response.output_item.added"), "output_index": .integer(index),
                "item": .object([
                    "id": .string("fc\(index)"), "call_id": .string("call\(index)"),
                    "type": .string("function_call"), "name": .string("exec"), "arguments": .string(""),
                ]),
            ])
        }
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 65_536)
        return try #require(decoder.append(ByteBuffer(string: "data: " + value.serialized() + "\n\n")).first)
    }
}
