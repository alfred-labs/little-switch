import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A remote compaction request answers with the structured compaction item")
    func responsesRemoteCompactionRewrap() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body:
                    #"{"id":"resp_prov","output":[{"type":"message","content":[{"type":"output_text","text":"Thread summary."}]}],"usage":null}"#
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let requestBody: [String: Any] = [
                "model": slug,
                "stream": true,
                "input": [
                    [
                        "type": "message", "role": "user",
                        "content": [["type": "input_text", "text": "Long thread"]],
                    ] as [String: Any],
                    ["type": "compaction_trigger"] as [String: Any],
                ],
            ]
            let response = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: try JSONSerialization.data(withJSONObject: requestBody))
            )
            #expect(response.status == .ok)
            let body = String(data: data(response.body), encoding: .utf8) ?? ""
            #expect(body.contains("event: response.output_item.done"))
            #expect(body.contains(#""type":"compaction""#))
            #expect(body.contains("little_switch_compaction"))
            #expect(body.contains("Thread summary."))
        }

        let upstream = try #require(await transport.requests.first)
        let upstreamBody = String(data: upstream.body, encoding: .utf8) ?? ""
        // The trigger never reaches the provider and the exchange is buffered
        // so the whole summary is available for the rewrap.
        #expect(!upstreamBody.contains("compaction_trigger"))
        #expect(upstreamBody.contains(#""stream":false"#))
    }

    @Test("Remote compaction surfaces upstream failure safely")
    func responsesRemoteCompactionUpstreamFailure() async throws {
        let ready = try makeFixture()
        let mapping = try #require(
            ready.snapshot.codex.resolvedDefaultModel(in: ready.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: ready.snapshot.providers)
        let body = ByteBuffer(
            bytes: try JSONSerialization.data(
                withJSONObject: [
                    "model": slug,
                    "stream": true,
                    "input": [
                        ["type": "message", "role": "user", "content": []] as [String: Any],
                        ["type": "compaction_trigger"] as [String: Any],
                    ],
                ] as [String: Any]
            )
        )

        try await makeApplication(
            fixture: ready,
            transport: FailingGatewayTransport(error: GatewayTestError.privateFailure)
        ).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: body
            )
            #expect(result.status == .badGateway)
        }
    }

    @Test("Remote compaction relays a provider error and rejects a summary-less body")
    func responsesRemoteCompactionBadSummaries() async throws {
        let ready = try makeFixture()
        let mapping = try #require(
            ready.snapshot.codex.resolvedDefaultModel(in: ready.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: ready.snapshot.providers)
        let body = ByteBuffer(
            bytes: try JSONSerialization.data(
                withJSONObject: [
                    "model": slug,
                    "stream": true,
                    "input": [
                        ["type": "message", "role": "user", "content": []] as [String: Any],
                        ["type": "compaction_trigger"] as [String: Any],
                    ],
                ] as [String: Any]
            )
        )
        // A 2xx body without any summary message is an invalid provider
        // response; a non-2xx answer relays buffered as-is; a body that
        // fails mid-collect surfaces as bad gateway.
        let upstreams: [HTTPClientResponse] = [
            response(status: .ok, body: #"{"id":"resp_x","output":[]}"#),
            response(status: .badGateway, body: #"{"error":"nope"}"#),
            failingResponse(error: GatewayTestError.privateFailure),
        ]
        for upstream in upstreams {
            try await makeApplication(
                fixture: ready,
                transport: RecordingGatewayTransport(responses: [upstream])
            ).test(.router) { client in
                let result = try await client.execute(
                    uri: "/v1/responses",
                    method: .post,
                    body: body
                )
                #expect(result.status == .badGateway)
            }
        }
    }

    @Test("Remote compaction mirrors serializer, builder, and cancellation failures")
    func responsesRemoteCompactionDependencyFailures() async throws {
        // A failing serializer surfaces the invalid-request error.
        let serializing = try makeFixture()
        let serializingApp = Application(
            responder: GatewayResponder(
                state: serializing.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: serializing.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(
                    serializer: FailingGatewaySerializer()
                )
            )
        )
        let serializingSlug = try responsesSlug(serializing)
        try await serializingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"\#(serializingSlug)","input":[{"type":"compaction_trigger"}]}"#
                )
            )
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Invalid Responses request"))
        }

        // A provider whose URL cannot build surfaces unavailable.
        let unbuildable = try providerFailureFixture(baseURL: "not-a-provider-url", includeSecret: true)
        try await makeApplication(
            fixture: unbuildable,
            transport: RecordingGatewayTransport(responses: [])
        ).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"\#(responsesSlug(unbuildable))","input":[{"type":"compaction_trigger"}]}"#
                )
            )
            #expect(result.status == .serviceUnavailable)
            #expect(String(buffer: result.body).contains("Provider is not ready"))
        }

        // Cancellation propagates without leaking the transport error shape.
        let cancelling = try makeFixture()
        let cancellingApp = Application(
            responder: GatewayResponder(
                state: cancelling.state,
                transport: CancellingGatewayTransport(),
                secretStore: cancelling.secrets,
                requiredAuthorityPort: nil
            )
        )
        try await cancellingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"\#(responsesSlug(cancelling))","input":[{"type":"compaction_trigger"}]}"#
                )
            )
            #expect(result.status == .internalServerError)
        }

        // A body that fails or cancels mid-collect reports and rethrows
        // directly, mirroring the adapter's buffered relay contract.
        let cancellingFixture = try makeFixture()
        let context = TransparentResponsesContext(
            body: Data(
                #"{"model":"route","input":[{"type":"compaction_trigger"}],"stream":true}"#.utf8
            ),
            model: "route",
            target: CodexModelTarget(
                provider: cancellingFixture.snapshot.providers[0],
                model: cancellingFixture.snapshot.providers[0].models[0]
            ),
            credential: nil,
            incomingHeaders: [:],
            eventID: UUID(),
            streaming: true
        )
        // Both a failing and a cancelled body rethrow the cancellation the
        // tracing body reduces every mid-stream failure to.
        for error in [GatewayTestError.privateFailure as any Swift.Error, CancellationError()] {
            let responder = GatewayResponder(
                state: cancellingFixture.state,
                transport: RecordingGatewayTransport(responses: [
                    failingResponse(status: .badGateway, error: error)
                ]),
                secretStore: cancellingFixture.secrets,
                requiredAuthorityPort: nil
            )
            await #expect(throws: CancellationError.self) {
                _ = try await responder.remoteCompactionResponsesResponse(context)
            }
        }
    }

    @Test("A websocket upgrade probe on responses switches Codex to HTTP, not a retry loop")
    func responsesWebsocketUpgradeSignalsHTTPFallback() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            // Codex's native provider streams each turn over a websocket
            // first and only falls back to HTTP SSE when the upgrade fails
            // with 426 Upgrade Required. Any other status — including the
            // router's default 405 — reads as a retryable stream error, so
            // the turn exhausts its retries on the websocket and dies.
            let probe = try await client.execute(
                uri: "/v1/responses",
                method: .get,
                headers: [
                    .connection: "Upgrade",
                    .upgrade: "websocket",
                ]
            )
            #expect(probe.status == .upgradeRequired)

            // A plain GET without upgrade intent is just the wrong method.
            let plainGet = try await client.execute(
                uri: "/v1/responses",
                method: .get,
                headers: HTTPFields()
            )
            #expect(plainGet.status == .methodNotAllowed)
            #expect(plainGet.headers[.allow] == "POST")

            // Any other upgrade protocol is likewise not this route's
            // handshake — it answers the plain wrong-method 405.
            let otherProtocol = try await client.execute(
                uri: "/v1/responses",
                method: .get,
                headers: [
                    .connection: "Upgrade",
                    .upgrade: "h2c",
                ]
            )
            #expect(otherProtocol.status == .methodNotAllowed)
            #expect(otherProtocol.headers[.allow] == "POST")
        }
    }
}
