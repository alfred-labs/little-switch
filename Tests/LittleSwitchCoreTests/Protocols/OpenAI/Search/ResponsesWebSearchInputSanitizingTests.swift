import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Responses web search input sanitizing")
struct ResponsesWebSearchInputSanitizingTests {
    private let configuration = WebSearchConfiguration(
        provider: .firecrawl,
        resultsLimit: 10,
        maximumUses: 3
    )

    private func body(input: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "model": "client-model",
                "input": input,
                "tools": [["type": "web_search"]],
            ]
        )
    }

    private func upstreamInput(
        _ prepared: PreparedResponsesWebSearchRequest
    ) throws -> [[String: Any]] {
        let object =
            try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        return object?["input"] as? [[String: Any]] ?? []
    }

    @Test("Client-only web_search_call items never reach the provider")
    func stripsWebSearchCallItems() throws {
        let body = try body(input: [
            ["type": "message", "role": "user", "content": []],
            ["type": "web_search_call", "id": "ws_1", "status": "completed"],
            ["type": "message", "role": "assistant", "content": []],
        ])

        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "upstream-model",
                configuration: configuration
            )
        )

        let types = try upstreamInput(prepared).compactMap { $0["type"] as? String }
        #expect(types == ["message", "message", "message"])
        #expect(try #require(String(bytes: prepared.upstreamBody, encoding: .utf8)).contains("Previous web search"))
    }

    @Test("The original input is preserved for the client projection")
    func keepsOriginalInput() throws {
        let body = try body(input: [
            ["type": "web_search_call", "id": "ws_1", "status": "completed"]
        ])

        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "upstream-model",
                configuration: configuration
            )
        )

        let original =
            try JSONSerialization.jsonObject(
                with: prepared.originalInputJSON,
                options: [.fragmentsAllowed]
            ) as? [[String: Any]]
        #expect(original?.compactMap { $0["type"] as? String } == ["web_search_call"])
    }

    @Test("Input untouched when it carries no fabricated item")
    func leavesRegularInputAlone() throws {
        let body = try body(input: [
            ["type": "message", "role": "user", "content": []],
            ["type": "reasoning", "id": "rs_1", "summary": []],
        ])

        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "upstream-model",
                configuration: configuration
            )
        )

        let types = try upstreamInput(prepared).compactMap { $0["type"] as? String }
        #expect(types == ["message", "reasoning"])
    }
}
