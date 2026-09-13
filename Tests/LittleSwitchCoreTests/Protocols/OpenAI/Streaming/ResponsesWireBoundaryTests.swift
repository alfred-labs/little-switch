import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses exact wire boundaries")
struct ResponsesWireBoundaryTests {
    @Test("An unknown provider event retains its complete original JSON bytes")
    func opaqueEventPreservesOriginalData() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 16_384)
        _ = try accumulator.consume(createdFrame(id: "resp_exact", createdAt: 1))
        let data = Data(
            #"{ "type": "response.vendor.delta", "opaque": {"huge": 18446744073709551617, "tiny": 1e-400, "null": null} }"#
                .utf8)

        #expect(
            try accumulator.consume(ServerSentEventFrame(event: nil, data: data, terminal: false))
                == [.passthrough(type: "response.vendor.delta", payloadJSON: data)])
    }

    @Test("A boolean cannot become a native stream output index")
    func booleanOutputIndexIsRejected() throws {
        var accumulator = OpenAIResponsesTurnAccumulator(maximumTurnBytes: 16_384)
        _ = try accumulator.consume(createdFrame(id: "resp_exact", createdAt: 1))
        let data = Data(
            #"{"type":"response.output_item.added","output_index":true,"item":{"id":"fc_1","type":"function_call","call_id":"call_1","name":"f","arguments":""}}"#
                .utf8)

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try accumulator.consume(ServerSentEventFrame(event: nil, data: data, terminal: false))
        }
    }

    @Test("Buffered Responses retain exact original response and opaque output numbers")
    func bufferedResponsePreservesOriginalData() throws {
        let data = Data(
            #"{ "id":"resp_exact", "object":"response", "status":"completed", "output":[{"type":"vendor_item","value":18446744073709551617,"tiny":1e-400}], "usage":{} }"#
                .utf8)
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(data)

        #expect(turn.rootJSON == data)
        #expect(
            try JSONValue.parse(turn.outputJSON)
                == JSONValue.parse(data).object?["output"])
    }
}
