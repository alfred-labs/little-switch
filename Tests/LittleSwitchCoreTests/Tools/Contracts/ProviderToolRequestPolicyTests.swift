import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider execution request policy")
struct ProviderToolRequestPolicyTests {
    @Test("Legacy hosted MCP cannot bypass tool declarations", arguments: [false, true])
    func hostedMCP(bridged: Bool) throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "model",
            "messages": [["role": "user", "content": "Hello"]],
            "mcp_servers": [["type": "url", "name": "remote", "url": "https://example.com/mcp"]],
            "tools": bridged ? [["type": "web_search_20250305", "name": "web_search"]] : [],
        ])
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            if bridged {
                _ = try AnthropicWebSearch.prepare(
                    body: body, targetModel: "upstream", configuration: .firecrawlCloud
                )
            } else {
                _ = try LiveGatewaySerializer().rewriteMessage(body, modelID: "upstream")
            }
        }
    }

    @Test("Empty legacy MCP and ordinary client MCP declarations remain allowed")
    func clientMCP() throws {
        try ProviderToolRequestPolicy.anthropic([
            "mcp_servers": [],
            "tools": [["name": "mcp__local__search", "input_schema": ["type": "object"]]],
        ])
    }

    @Test("An adapted Responses request cannot silently discard custom tools", arguments: [false, true])
    func customAdaptation(namespaced: Bool) throws {
        let custom: [String: Any] = ["type": "custom", "name": "edit", "format": ["type": "text"]]
        let declaration: [String: Any] =
            namespaced
            ? ["type": "namespace", "name": "files", "tools": [custom]] : custom
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "model", "input": "Hello", "tools": [["type": "web_search"], declaration],
        ])
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            _ = try OpenAIResponsesWebSearch.prepare(
                body: body, targetModel: "upstream", configuration: .firecrawlCloud
            )
        }
    }

    @Test("Native custom tools without adaptation remain protocol transparent")
    func transparentCustom() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "model", "input": "Hello", "tools": [["type": "custom", "name": "edit"]],
        ])
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: body, targetModel: "upstream", configuration: .disabled
            ) == nil
        )
    }

    @Test("Protocol message shorthand is allowed and malformed tool containers fail")
    func containerValidation() throws {
        try ProviderToolRequestPolicy.responses(["input": [["role": "user", "content": "Hello"]]])
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            try ProviderToolRequestPolicy.responses(["tools": "function"])
        }
        #expect(throws: ProviderToolContract.Error.invalidRequest) {
            try ProviderToolRequestPolicy.anthropic(["mcp_servers": "remote"])
        }
    }
}
