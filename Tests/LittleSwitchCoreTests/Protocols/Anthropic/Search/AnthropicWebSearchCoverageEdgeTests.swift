import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic web search projection coverage edges")
struct AnthropicWebSearchCoverageEdgeTests {
    @Test("Trace content requires a typed block envelope")
    func malformedTraceBlockEnvelope() throws {
        let trace = WebSearchTrace(
            toolUseID: "srvtoolu_coverage",
            query: "Swift",
            content: .results([]),
            publicContentJSON: try JSONSerialization.data(withJSONObject: [[String: Any]()])
        )

        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            _ = try AnthropicWebSearch.responseContent(
                traces: [trace],
                finalTurn: coverageFinalTurn
            )
        }
    }

    @Test("Streaming block projection rejects missing typed payloads")
    func malformedStreamingBlocks() {
        let malformedBlocks: [[String: Any]] = [
            ["type": "server_tool_use"],
            ["type": "tool_use"],
            ["type": "text"],
            ["type": "thinking"],
        ]

        for block in malformedBlocks {
            var stream = Data()
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.appendStreamingBlock(anthropicTestObject(block), index: 0, to: &stream)
            }
        }
    }
}

private let coverageFinalTurn = AnthropicModelTurn(
    id: "msg_coverage",
    contentJSON: Data("[]".utf8),
    stopReason: "end_turn",
    stopSequenceJSON: nil,
    usage: AnthropicUsage(inputTokens: 1, outputTokens: 1),
    webSearchCall: nil
)
