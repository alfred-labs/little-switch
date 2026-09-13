import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Chat wire number boundaries")
struct ChatWireNumberBoundaryTests {
    @Test("Choice indexes must be exact nonnegative integers", arguments: ["true", "0.00000000000000000000001", "-1"])
    func rejectsNonIntegralChoiceIndex(index: String) throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try liveChatPrepared())
        let payload = """
            {"id":"chat","object":"chat.completion.chunk","created":1,"model":"provider",
             "choices":[{"index":\(index),"delta":{"content":"hello"},"finish_reason":null}]}
            """
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try accumulator.consume(ServerSentEventFrame(event: nil, data: Data(payload.utf8), terminal: false))
        }
    }

    @Test("A fractional creation timestamp cannot become an integer through rounding")
    func rejectsRoundedTimestamp() throws {
        var accumulator = OpenAIChatCompletionsAccumulator(prepared: try liveChatPrepared())
        let payload = """
            {"id":"chat","object":"chat.completion.chunk","created":1.00000000000000000000001,
             "model":"provider","choices":[]}
            """
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            try accumulator.consume(ServerSentEventFrame(event: nil, data: Data(payload.utf8), terminal: false))
        }
    }
}
