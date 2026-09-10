import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Responses search refusal")
struct GatewayResponsesSearchRefusalTests {
    @Test(
        "Refused search preserves public names without reading search credentials",
        arguments: ResponsesSearchRefusalWire.allCases, ResponsesSearchRefusalMode.allCases
    )
    func namespaceCalls(wire: ResponsesSearchRefusalWire, mode: ResponsesSearchRefusalMode) async throws {
        try await verifyCall(wire: wire, mode: mode, replay: false)
    }

    @Test(
        "Replay drops a refused forced search and keeps collaboration callable",
        arguments: ResponsesSearchRefusalWire.allCases
    )
    func forcedSearchReplay(wire: ResponsesSearchRefusalWire) async throws {
        try await verifyCall(wire: wire, mode: .buffered, replay: true)
    }

    @Test(
        "An MCP search tool remains a public client call",
        arguments: ResponsesSearchRefusalWire.allCases, ResponsesSearchRefusalMode.allCases
    )
    func namespacedSearch(wire: ResponsesSearchRefusalWire, mode: ResponsesSearchRefusalMode) async throws {
        try await verifyCall(
            wire: wire,
            mode: mode,
            replay: false,
            binding: ResponsesToolNamespaces.Binding(namespace: "mcp", name: "web_search")
        )
    }

    @Test(
        "A restored local name cannot select a different namespace",
        arguments: ResponsesSearchRefusalWire.allCases, ResponsesSearchRefusalMode.allCases
    )
    func overlappingNames(wire: ResponsesSearchRefusalWire, mode: ResponsesSearchRefusalMode) async throws {
        try await verifyCall(
            wire: wire,
            mode: mode,
            replay: false,
            binding: ResponsesToolNamespaces.Binding(namespace: "b", name: "a__foo"),
            competingTool: true
        )
    }

    @Test(
        "Unexpected model search calls cannot spend a refused search budget",
        arguments: ResponsesSearchRefusalWire.allCases, ResponsesSearchRefusalMode.allCases
    )
    func unexpectedSearchCall(wire: ResponsesSearchRefusalWire, mode: ResponsesSearchRefusalMode) async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(
            providerID: provider.id, supportsNative: wire == .native
        )
        let transport = RecordingGatewayTransport(responses: [
            try refusalFunctionResponse(
                wire: wire,
                streaming: mode.providerStreaming,
                functionName: "web_search",
                arguments: #"{"query":"Swift"}"#
            ),
            try refusalFunctionResponse(wire: wire, streaming: mode.providerStreaming),
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let body = ByteBuffer(
            bytes: try responseData([
                "model": slug, "stream": mode.clientStreaming,
                "input": [
                    ["type": "message", "role": "user", "content": "Continue."],
                    ["type": "web_search_call", "id": "ws_previous", "status": "completed"],
                ],
                "tools": [["type": "web_search", "external_web_access": false]],
            ]))
        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: body)
            #expect(result.status == (mode.providerStreaming ? .ok : .badGateway))
            if mode.providerStreaming {
                let events = try ResponsesStreamingTestSupport.events(Data(result.body.readableBytesView))
                #expect(events.last?.name == "response.failed")
            }
        }

        let requests = await transport.requests
        #expect(requests.allSatisfy { !$0.url.contains("firecrawl") })
        #expect(requests.count == 1)
    }

    private func verifyCall(
        wire: ResponsesSearchRefusalWire,
        mode: ResponsesSearchRefusalMode,
        replay: Bool,
        binding: ResponsesToolNamespaces.Binding = .init(namespace: "collaboration", name: "spawn_agent"),
        competingTool: Bool = false
    ) async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(
            providerID: provider.id, supportsNative: wire == .native
        )
        let wireName = "\(binding.namespace)__\(binding.name)"
        let transport = RecordingGatewayTransport(responses: [
            try refusalFunctionResponse(wire: wire, streaming: mode.providerStreaming, functionName: wireName)
        ])
        let recorder = TrafficTestRecorder()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: SearchThrowingGatewaySecretStore(
                    providerID: provider.id, providerSecret: "selected-secret"
                ),
                requiredAuthorityPort: nil,
                trafficRecorder: recorder
            )
        )
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let body = ByteBuffer(
            bytes: try refusalRequestBody(
                slug: slug,
                streaming: mode.clientStreaming,
                replay: replay,
                binding: binding,
                competingTool: competingTool
            ))
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: body
            )
            try #require(result.status == .ok)
            let data = Data(result.body.readableBytesView)
            let response: [String: Any]
            if mode.clientStreaming {
                let events = try ResponsesStreamingTestSupport.events(data)
                #expect(events.last?.name == "response.completed")
                response = try #require(events.last?.payload["response"] as? [String: Any])
                let argumentEvents = events.filter {
                    $0.name == "response.function_call_arguments.done"
                }
                #expect(!argumentEvents.isEmpty)
                #expect(argumentEvents.allSatisfy { $0.payload["name"] as? String == binding.name })
            } else {
                response = try responsesGatewayObject(data)
            }
            let output = try #require(response["output"] as? [[String: Any]])
            let call = try #require(output.first { $0["type"] as? String == "function_call" })
            #expect(call["name"] as? String == binding.name)
            #expect(call["namespace"] as? String == binding.namespace)
            #expect(try !#require(String(data: data, encoding: .utf8)).contains(wireName))
        }

        let requests = await transport.requests
        try #require(requests.count == 1)
        let upstream = try responsesGatewayObject(requests[0].body)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        let names = tools.compactMap { tool in
            switch wire {
            case .native: tool["name"] as? String
            case .chatCompletions: (tool["function"] as? [String: Any])?["name"] as? String
            }
        }
        #expect(names == (competingTool ? ["a__foo", wireName] : [wireName]))
        if replay {
            #expect(upstream["tool_choice"] as? String == "auto")
        } else if binding.name == "web_search" {
            let expectedChoice: [String: Any] =
                switch wire {
                case .native: ["type": "function", "name": wireName]
                case .chatCompletions: ["type": "function", "function": ["name": wireName]]
                }
            #expect(try responseData(upstream["tool_choice"] as Any) == responseData(expectedChoice))
        }
        #expect(recorder.events.allSatisfy { $0.failure == nil })
    }

    private func refusalRequestBody(
        slug: String,
        streaming: Bool,
        replay: Bool,
        binding: ResponsesToolNamespaces.Binding,
        competingTool: Bool
    ) throws -> Data {
        let additionalTools: [[String: Any]] =
            competingTool
            ? [
                [
                    "type": "namespace", "name": "a",
                    "tools": [["type": "function", "name": "foo", "parameters": ["type": "object"]]],
                ]
            ] : []
        var request: [String: Any] = [
            "model": slug, "input": "Call the collaboration tool.", "stream": streaming,
            "tools": additionalTools + [
                ["type": "web_search", "external_web_access": false],
                [
                    "type": "namespace", "name": binding.namespace,
                    "tools": [
                        [
                            "type": "function", "name": binding.name,
                            "parameters": ["type": "object", "properties": [:]],
                        ]
                    ],
                ],
            ],
        ]
        if replay {
            request["input"] = [
                ["type": "message", "role": "user", "content": "Continue."],
                ["type": "web_search_call", "id": "ws_previous", "status": "completed"],
            ]
            request["tool_choice"] = ["type": "web_search"]
        } else if binding.name == "web_search" {
            request["tool_choice"] = [
                "type": "function", "name": binding.name, "namespace": binding.namespace,
            ]
        }
        return try responseData(request)
    }
}
