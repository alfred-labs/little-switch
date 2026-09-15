import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway cold custom capability probes")
struct GatewayCustomToolProbeLifecycleTests {
    @Test(
        "A cold non-native verdict adapts the model exchange and traces no synthetic probes", arguments: [false, true])
    func coldCache(chat: Bool) async throws {
        let fixture = GatewayCustomProbeFixture(chat: chat)
        let cache = CustomToolCapabilityCache()
        let state = GatewayState(
            snapshot: RoutingSnapshot(generation: 0, providers: [fixture.provider], mappings: [:]),
            customToolCapabilities: cache)
        let raw =
            chat
            ? #"""
            {"choices":[{"index":0,"message":{"role":"assistant","tool_calls":[
              {"id":"call","type":"function","function":{"name":"exec","arguments":"{\"input\":\"done\"}"}}
            ]},"finish_reason":"tool_calls"}]}
            """#
            : #"{"output":[{"type":"function_call","id":"fc","call_id":"call","name":"exec","arguments":"{\"input\":\"done\"}"}]}"#
        let transport = CustomCapabilityProbeTransport([.noCall, .echo, .http(200, raw)])
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: state, transport: transport, secretStore: MemorySecretStore(), trafficRecorder: recorder)
        let exchange = try await responder.executeModelRequest(
            fixture.request,
            body: fixture.body,
            traffic: fixture.traffic,
            wire: fixture.wire,
            eventID: UUID(),
            attempt: 0)
        let output = try JSONValue.parse(await exchange.trace.collect(exchange.response.body, upTo: 65_536))
        let expected =
            chat
            ? #"""
            {"choices":[{"index":0,"message":{"role":"assistant","tool_calls":[
              {"id":"call","type":"custom","custom":{"name":"exec","input":"done"}}
            ]},"finish_reason":"tool_calls"}]}
            """#
            : #"{"output":[{"type":"custom_tool_call","id":"fc","call_id":"call","name":"exec","input":"done"}]}"#
        #expect(output == (try JSONValue.parse(Data(expected.utf8))))
        let requests = await transport.requests
        #expect(requests.count == 3)
        let actual = try #require(requests.last)
        let actualTool = try JSONValue.parse(actual.body).object?["tools"]?.array?.first
        #expect(actualTool?.object?["type"] == .string("function"))
        for probe in requests.dropLast() {
            #expect(!probe.body.contains(Data("synthetic-client-content".utf8)))
            #expect(probe.body.contains(Data("littleswitch_custom_probe".utf8)))
        }
        let traces = recorder.events.flatMap(\.upstreamExchanges)
        #expect(traces.count == 1)
        #expect(traces.first?.request?.body == actual.body)
        #expect(traces.first?.response.body == Data(raw.utf8))
        let cached = try await responder.customToolProjection(
            request: fixture.request, body: fixture.body, traffic: fixture.traffic, wire: fixture.wire)
        #expect(!cached.isIdentity)
        #expect(await transport.requests.count == 3)
    }

    @Test("A provider absent from the fresh routing capture cannot start a probe")
    func absentProvider() async throws {
        let fixture = GatewayCustomProbeFixture(chat: false)
        let state = GatewayState(
            snapshot: RoutingSnapshot(generation: 0, providers: [], mappings: [:]),
            customToolCapabilities: CustomToolCapabilityCache())
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(state: state, transport: transport, secretStore: MemorySecretStore())
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await responder.executeModelRequest(
                fixture.request,
                body: fixture.body,
                traffic: fixture.traffic,
                wire: fixture.wire,
                eventID: UUID(),
                attempt: 0)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("A credential revision during probing cancels publication and the next turn obtains fresh evidence")
    func revisionDuringProbe() async throws {
        let fixture = GatewayCustomProbeFixture(chat: false)
        let state = GatewayState(
            snapshot: RoutingSnapshot(generation: 0, providers: [fixture.provider], mappings: [:]),
            customToolCapabilities: CustomToolCapabilityCache())
        let transport = GatewayCustomRevisionTransport(state: state, provider: fixture.provider)
        let responder = GatewayResponder(state: state, transport: transport, secretStore: MemorySecretStore())
        await #expect(throws: CancellationError.self) {
            try await responder.executeModelRequest(
                fixture.request,
                body: fixture.body,
                traffic: fixture.traffic,
                wire: fixture.wire,
                eventID: UUID(),
                attempt: 0)
        }
        let next = try await responder.customToolProjection(
            request: fixture.request, body: fixture.body, traffic: fixture.traffic, wire: fixture.wire)
        #expect(!next.isIdentity)
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.body.contains(Data("littleswitch_custom_probe".utf8)) })
    }
}

private struct GatewayCustomProbeFixture {
    let provider = Provider(name: "Test", baseURL: "https://unit.example/v1", authMode: .none)
    let wire: ProviderToolContract.Wire
    let body: Data

    init(chat: Bool) {
        wire = chat ? .chatCompletions : .responses
        body = Data(
            (chat
                ? #"{"model":"m","tools":[{"type":"custom","custom":{"name":"exec"}}],"messages":[{"role":"user","content":"synthetic-client-content"}]}"#
                : #"{"model":"m","tools":[{"type":"custom","name":"exec"}],"input":"synthetic-client-content"}"#).utf8)
    }

    var request: HTTPClientRequest {
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.body = .bytes(ByteBuffer(bytes: body))
        return request
    }

    var traffic: TrafficUpstreamRequest {
        TrafficUpstreamRequest(
            attempt: 0,
            claudeRoute: "m",
            providerID: provider.id,
            providerName: provider.name,
            modelID: "m",
            url: url,
            headers: [],
            body: body,
            streaming: false)
    }

    private var url: String { provider.baseURL + (wire == .responses ? "/responses" : "/chat/completions") }
}

private actor GatewayCustomRevisionTransport: UpstreamTransport {
    let state: GatewayState
    let provider: Provider
    let inner = CustomCapabilityProbeTransport([.echo, .noCall, .echo])
    private var invalidated = false

    init(state: GatewayState, provider: Provider) {
        self.state = state
        self.provider = provider
    }

    var requests: [RecordedGatewayRequest] { get async { await inner.requests } }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        try await execute(request, timeout: .seconds(0))
    }

    func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse {
        let response = try await inner.execute(request, timeout: timeout)
        if !invalidated {
            invalidated = true
            await state.replace(providers: [provider], mappings: [:], credentialChangedProviderIDs: [provider.id])
        }
        return response
    }
}
