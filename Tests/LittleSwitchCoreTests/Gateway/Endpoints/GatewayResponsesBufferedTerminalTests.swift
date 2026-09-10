import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway buffered Responses terminal preservation")
struct GatewayResponsesBufferedTerminalTests {
    @Test(
        "Namespace, discovery, and refused-search adaptation retain the provider terminal",
        arguments: ResponsesBufferedTerminalCase.allCases, ResponsesBufferedAdaptation.allCases
    )
    func adaptedTerminals(
        testCase: ResponsesBufferedTerminalCase,
        adaptation: ResponsesBufferedAdaptation
    ) async throws {
        let fixture: GatewayFixture
        if adaptation == .refusedSearch {
            fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        } else {
            fixture = try GatewayTests().makeFixture()
        }
        try await verify(
            fixture: fixture,
            testCase: testCase,
            tools: adaptation.tools,
            providerBody: testCase.body()
        )
    }

    @Test("Native failed responses retain their terminal when usage is absent or null", arguments: [false, true])
    func failedWithoutUsage(omitted: Bool) async throws {
        let testCase = ResponsesBufferedTerminalCase.nativeFailure
        var provider = try responsesGatewayObject(testCase.body())
        provider["usage"] = omitted ? nil : NSNull()
        try await verify(
            fixture: GatewayTests().makeFixture(),
            testCase: testCase,
            tools: ResponsesBufferedAdaptation.namespace.tools,
            providerBody: responseData(provider)
        )
    }

    @Test("A native failed response without output preserves the same failure as live fallback")
    func failedWithoutOutput() async throws {
        var provider = try responsesGatewayObject(Data(nativeFailedJSON(code: "context_length_exceeded").utf8))
        provider["incomplete_details"] = NSNull()
        try await verify(
            fixture: GatewayTests().makeFixture(),
            testCase: .nativeContextLimit,
            tools: ResponsesBufferedAdaptation.namespace.tools,
            providerBody: responseData(provider),
            expectedOutputCount: 0
        )
    }

    @Test(
        "Incomplete and failed model turns cannot execute an emitted private search call",
        arguments: ResponsesBufferedTerminalCase.allCases.filter { $0.status != "completed" }
    )
    func interruptedPrivateSearch(testCase: ResponsesBufferedTerminalCase) async throws {
        try await verify(
            fixture: GatewayTests().makeResponsesWebSearchFixture(),
            testCase: testCase,
            tools: [["type": "web_search"]],
            providerBody: testCase.body(privateSearchCall: true)
        )
    }

    private func verify(
        fixture: GatewayFixture,
        testCase: ResponsesBufferedTerminalCase,
        tools: [[String: Any]],
        providerBody: Data,
        expectedOutputCount: Int = 1
    ) async throws {
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(
            providerID: provider.id, supportsNative: testCase.supportsNative
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: try #require(String(data: providerBody, encoding: .utf8)))
        ])
        let app = GatewayTests().makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let expectedToolsJSON = try responseData(tools)
        let body = ByteBuffer(
            bytes: try responseData([
                "model": slug, "input": "Hello", "stream": false, "tools": tools,
            ]))
        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: body)
            let requests = await transport.requests
            #expect(requests.count == 1)
            #expect(requests.allSatisfy { !$0.url.contains("firecrawl") })
            #expect(requests.first?.url.hasSuffix(testCase.supportsNative ? "/responses" : "/chat/completions") == true)
            try #require(result.status == .ok)
            let object = try responsesGatewayObject(Data(result.body.readableBytesView))
            try testCase.expectTerminal(object)
            #expect(object["model"] as? String == slug)
            #expect(try responseData(#require(object["tools"])) == expectedToolsJSON)
            let output = try #require(object["output"] as? [[String: Any]])
            #expect(output.count == expectedOutputCount)
            if expectedOutputCount > 0 {
                let content = try #require(output.first?["content"] as? [[String: Any]])
                #expect(content.first?["text"] as? String == "Partial answer")
            }
            #expect(!output.contains { $0["type"] as? String == "web_search_call" })
        }
    }
}
