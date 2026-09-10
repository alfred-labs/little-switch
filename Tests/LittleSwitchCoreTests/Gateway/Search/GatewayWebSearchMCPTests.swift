import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("MCP advertises the managed web search tool")
    func webSearchMCPCatalog() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/mcp",
                method: .post,
                headers: webSearchMCPHeaders,
                body: ByteBuffer(string: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
            )
            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            #expect(object["jsonrpc"] as? String == "2.0")
            #expect(object["id"] as? Int == 1)
            let payload = try #require(object["result"] as? [String: Any])
            let tools = try #require(payload["tools"] as? [[String: Any]])
            #expect(tools.count == 1)
            #expect(tools.first?["name"] as? String == "search")
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("MCP negotiates versions and acknowledges notifications without sessions")
    func webSearchMCPLifecycle() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            for version in ["2025-03-26", "2025-06-18", "2025-11-25", "unknown"] {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(
                        string:
                            #"{"jsonrpc":"2.0","id":"init","method":"initialize","params":{"protocolVersion":"\#(version)","#
                            + #""capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
                    )
                )
                #expect(result.status == .ok)
                #expect(result.headers[.contentType] == "application/json")
                let object = try anthropicObject(data(result.body))
                let payload = try #require(object["result"] as? [String: Any])
                #expect(object["id"] as? String == "init")
                #expect(
                    payload["protocolVersion"] as? String
                        == (["unknown", "2025-03-26"].contains(version) ? "2025-11-25" : version))
                let capabilities = try #require(payload["capabilities"] as? [String: Any])
                #expect(Set(capabilities.keys) == ["tools"])
                let info = try #require(payload["serverInfo"] as? [String: Any])
                #expect(info["name"] as? String == "LittleSwitch")
                #expect(info["version"] as? String == ApplicationBuild.currentTag)
            }
            let notification = try await client.execute(
                uri: "/api/mcp",
                method: .post,
                headers: webSearchMCPHeaders,
                body: ByteBuffer(string: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
            )
            #expect(notification.status == .accepted)
            #expect(notification.body.readableBytes == 0)
            let ping = try await client.execute(
                uri: "/api/mcp",
                method: .post,
                headers: webSearchMCPHeaders,
                body: ByteBuffer(string: #"{"jsonrpc":"2.0","id":0,"method":"ping"}"#)
            )
            #expect(ping.status == .ok)
            #expect(try mcpJSONEqual(data(ping.body), #"{"jsonrpc":"2.0","id":0,"result":{}}"#))
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test(
        "MCP searches through the selected provider and returns portable sources",
        arguments: [WebSearchProvider.firecrawl, .tavily, .brave, .exa], ["search", "web_search"])
    func webSearchMCPProvider(provider: WebSearchProvider, toolName: String) async throws {
        let fixture = try makeWebSearchFixture(provider: provider)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: gatewaySearchResponseBody(provider: provider))
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/mcp",
                method: .post,
                headers: webSearchMCPHeaders,
                body: ByteBuffer(
                    string: webSearchMCPCall.replacingOccurrences(
                        of: "\"name\":\"search\"", with: "\"name\":\"\(toolName)\""))
            )
            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            #expect(object["id"] as? String == "search")
            let payload = try #require(object["result"] as? [String: Any])
            #expect(payload["isError"] as? Bool == false)
            let structured = try #require(payload["structuredContent"] as? [String: Any])
            let expected =
                #"{"results":[{"title":"Swift.org","url":"https://swift.org/","snippet":"The Swift project website"}]}"#
            #expect(try mcpJSONEqual(JSONSerialization.data(withJSONObject: structured), expected))
            let content = try #require(payload["content"] as? [[String: Any]])
            #expect(content.count == 1)
            #expect(content.first?["type"] as? String == "text")
            let text = try #require(content.first?["text"] as? String)
            #expect(try mcpJSONEqual(Data(text.utf8), expected))
            #expect(await transport.requests.count == 1)
            let searches = recorder.events.flatMap(\.webSearches)
            #expect(searches.count == 1)
            #expect(searches.first?.provider == provider.rawValue)
            #expect(searches.first?.query == "Swift release")
        }
    }
}

var webSearchMCPHeaders: HTTPFields {
    [.contentType: "application/json", .accept: "application/json, text/event-stream"]
}

var webSearchMCPCall: String {
    #"{"jsonrpc":"2.0","id":"search","method":"tools/call","params":{"name":"search","arguments":{"query":"Swift release"}}}"#
}

func mcpJSONEqual(_ data: Data, _ expected: String) throws -> Bool {
    let left = try JSONSerialization.jsonObject(with: data)
    let right = try JSONSerialization.jsonObject(with: Data(expected.utf8))
    return try JSONSerialization.data(withJSONObject: left, options: [.sortedKeys])
        == JSONSerialization.data(withJSONObject: right, options: [.sortedKeys])
}
