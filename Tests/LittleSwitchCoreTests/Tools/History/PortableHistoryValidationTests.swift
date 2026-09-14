import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Portable history validation")
struct PortableHistoryValidationTests {
    @Test("Malformed server result containers and flags fail before replay")
    func invalidResultContainers() throws {
        let call: [String: Any] = ["type": "server_tool_use", "id": "server", "name": "analyze_image", "input": [:]]
        let result: [String: Any] = ["type": "tool_result", "tool_use_id": "server", "content": "Image description"]
        var badFlag = result
        badFlag["is_error"] = "false"
        var missingContent = result
        missingContent.removeValue(forKey: "content")
        let cases: [[Any]] = [[call, result, 1], [call, badFlag], [call, missingContent]]
        for content in cases {
            #expect(throws: (any Error).self) {
                try anthropicPortableHistory(["messages": [["role": "assistant", "content": content]]])
            }
        }
    }

    @Test("Published web results and citation metadata remain readable after a provider switch")
    func typedSearchAndCitationMetadata() throws {
        let content = try AnthropicWebSearch.responseContent(
            traces: [
                WebSearchTrace(
                    toolUseID: "server",
                    query: "Swift",
                    content: .results([WebSearchResult(title: "Swift", url: "https://swift.org/", content: "Actors")])
                )
            ],
            finalTurn: bareAnthropicTurn(contentJSON: Data("[]".utf8))
        )
        let root = try anthropicPortableHistory([
            "messages": [["role": "assistant", "content": content.map(anthropicFoundationObject)]]
        ])
        let data = try JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains("Actors"))
        #expect(text.contains("https://swift.org/"))
        #expect(!text.contains("encrypted_content"))

        let citation: [String: Any] = [
            "type": "text", "text": "A citation", "citations": [["url": "https://swift.org/"]],
        ]
        let blocks: [[String: Any]] = [
            ["type": "server_tool_use", "id": "image", "name": "analyze_image", "input": [:]],
            ["type": "tool_result", "tool_use_id": "image", "content": [citation]],
            ["opaque_metadata": "preserved"],
        ]
        let replay = try anthropicPortableHistory(["messages": [["role": "assistant", "content": blocks]]])
        let messages = try #require(replay["messages"] as? [[String: Any]])
        let rewritten = try #require(messages.first?["content"] as? [[String: Any]])
        #expect((rewritten[1]["text"] as? String)?.contains("citations") == true)
        #expect(rewritten.last?["opaque_metadata"] as? String == "preserved")
    }

    @Test("Public search history does not accept an unrelated item")
    func unrelatedResponsesItem() {
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            try PortableResponsesHistory.message(for: [
                "type": "function_call", "id": "fc_1", "call_id": "call_1",
                "name": "client", "arguments": "{}", "status": "completed",
            ])
        }
    }

    @Test("Messages requires a JSON object")
    func invalidMessageRoot() {
        #expect(throws: (any Error).self) {
            try LiveGatewaySerializer().rewriteMessage(Data("[]".utf8), modelID: "model")
        }
    }
}
