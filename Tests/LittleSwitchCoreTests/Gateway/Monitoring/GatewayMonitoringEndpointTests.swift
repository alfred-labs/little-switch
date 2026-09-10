import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@Suite("Gateway monitoring endpoints")
struct GatewayMonitoringEndpointTests {
    @Test("One synthetic provider request is measured independently of detailed captures")
    func providerRequestAndRepeatedScrapes() async throws {
        let fixture = try GatewayTests().makeFixture()
        let store = MonitoringStore()
        let recorder = TrafficTestRecorder()
        let providerBody =
            #"{"type":"message","content":[{"type":"text","text":"PRIVATE_REPLY"}],"usage":{"input_tokens":6,"output_tokens":2,"cache_read_input_tokens":3}}"#
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: providerBody)])
        let monitoring = GatewayMonitoring(store: store) { .init(exposeLogs: true) }
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder,
                monitoring: monitoring))
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json", .authorization: "PRIVATE_TOKEN"],
                body: .init(
                    string: #"{"model":"claude-opus-5","messages":[{"role":"user","content":"PRIVATE_PROMPT"}]}"#))
            #expect(response.status == .ok)
            #expect(String(buffer: response.body) == providerBody)
            let before = await store.snapshot(
                at: store.resource.startedAt, providerPool: fixture.state.requestPoolSnapshot())
            let beforeLogs = try await store.logs()
            let beforeCaptures = recorder.events
            #expect(before.family(.requests)?.points.map(\.value) == [.counter(1)])
            #expect(before.family(.inFlight)?.points.map(\.value) == [.gauge(0)])
            #expect(beforeLogs.entries.count == 1)
            #expect(
                beforeLogs.entries[0].attributes.usage == .init(inputTokens: 6, outputTokens: 2, cacheReadTokens: 3))
            for _ in 0..<100 {
                let metrics = try await client.execute(uri: "/metrics", method: .get)
                let logs = try await client.execute(uri: "/logs", method: .get)
                #expect(metrics.status == .ok)
                #expect(logs.status == .ok)
                #expect(metrics.headers[.cacheControl] == "no-store")
                #expect(!String(buffer: logs.body).contains("PRIVATE_"))
            }
            #expect(await store.snapshot(at: store.resource.startedAt) == before)
            #expect(try await store.logs().entries == beforeLogs.entries)
            #expect(recorder.events == beforeCaptures)
        }
    }

    @Test("Access, disabling, methods, filters and negotiated format share the common responder")
    func accessAndFormats() async throws {
        let fixture = try GatewayTests().makeFixture()
        let recorder = TrafficTestRecorder()
        let monitoring = GatewayMonitoring(store: MonitoringStore())
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder,
            monitoring: monitoring)
        let app = Application(responder: responder)
        try await app.test(.router) { client in
            let disabled = try await client.execute(uri: "/logs", method: .post)
            #expect(disabled.status == .notFound)
            let method = try await client.execute(uri: "/metrics", method: .post)
            #expect(method.status == .methodNotAllowed)
            #expect(method.headers[.allow] == "GET")
            let forbidden = try await client.execute(
                uri: "/logs", method: .get, headers: [.origin: "https://untrusted.example"])
            #expect(forbidden.status == .forbidden)
            let openMetrics = try await client.execute(
                uri: "/metrics", method: .get, headers: [.accept: "application/openmetrics-text; version=1.0.0"])
            #expect(openMetrics.headers[.contentType]?.contains("application/openmetrics-text") == true)
            #expect(String(buffer: openMetrics.body).hasSuffix("# EOF\n"))
            let unacceptable = try await client.execute(
                uri: "/metrics", method: .get, headers: [.accept: "application/json"])
            #expect(unacceptable.status == .notAcceptable)
            #expect(recorder.events.isEmpty)
        }
        let channel = EmbeddedChannel()
        let context = BasicRequestContext(source: .init(channel: channel, logger: Logger(label: #function)))
        let request = Request(
            head: HTTPRequest(method: .get, scheme: "http", authority: "untrusted.example", path: "/metrics"),
            body: RequestBody(buffer: ByteBuffer()))
        let forbiddenHost = try await responder.respond(to: request, context: context)
        #expect(forbiddenHost.status == .forbidden)
        _ = try channel.finish()
    }
}
