import Foundation
import Testing

@testable import LittleSwitchCore

extension OpenAIResponsesChatCompletionsTests {
    @Test("Native custom tool history becomes readable Chat context")
    func preparesCustomToolHistory() throws {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"message","role":"user","content":[{"type":"input_text","text":"Run it."}]},
                {"type":"custom_tool_call","call_id":"call_9","name":"node_repl","input":"console.log('hi')"},
                {"type":"custom_tool_call_output","call_id":"call_9","output":"hi"}
              ],
              "stream":true
            }
            """#.utf8
        )

        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: "glm-5.3-flash"
        )
        let request = try #require(
            JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )
        let messages = try #require(request["messages"] as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String } == ["user", "assistant", "assistant"])
        #expect((messages[1]["content"] as? String)?.contains("node_repl") == true)
        #expect((messages[2]["content"] as? String)?.contains("hi") == true)
    }

    @Test("Custom tool history without a call id is rejected")
    func rejectsAnonymousCustomToolHistory() {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"custom_tool_call","name":"node_repl","input":"console.log('hi')"}
              ],
              "stream":true
            }
            """#.utf8
        )

        #expect(throws: OpenAIResponsesChatCompletions.Error.self) {
            _ = try OpenAIResponsesChatCompletions.prepare(
                body: body,
                targetModel: "glm-5.3-flash"
            )
        }
    }

    @Test("Chat history drops compaction markers")
    func chatDropsCompactionMarkers() throws {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "input":[
                {"type":"message","role":"user","content":[{"type":"input_text","text":"Run it."}]},
                {"type":"compaction_trigger"}
              ],
              "stream":true
            }
            """#.utf8
        )

        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: "glm-5.3-flash"
        )
        let request = try #require(
            JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )
        let messages = try #require(request["messages"] as? [[String: Any]])
        // The compaction marker leaves no message behind.
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
    }
}
