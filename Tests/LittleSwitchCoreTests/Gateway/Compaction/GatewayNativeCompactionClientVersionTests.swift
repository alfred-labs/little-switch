import Foundation
import LittleSwitchTransport
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayNativeCompactionRecoveryTests {
    @Test("The Desktop user agent and version header both carry client_version")
    func desktopDiscoveryCarriesClientVersion() async throws {
        // Codex Desktop's agent puts the CLI version on a separate
        // `Desktop/0.153.4` token with the bare word `Codex` in front, and
        // the request also carries a `version` header. Without either, the
        // backend answers 422 missing client_version (observed switching a
        // native conversation to a managed model).
        let desktopUA = "Codex Desktop/0.153.4 (Mac OS 26.6.2; arm64) unknown (Codex Desktop; 26.908.31748)"
        let cases: [(HTTPHeaders, String)] = [
            (
                [
                    "authorization": "Bearer synthetic-openai",
                    "chatgpt-account-id": "synthetic-account",
                    "user-agent": desktopUA,
                ],
                "0.153.4"
            ),
            (
                [
                    "authorization": "Bearer synthetic-openai",
                    "chatgpt-account-id": "synthetic-account",
                    "user-agent": "generic-agent/1.0",
                    "version": "0.154.0",
                ],
                "0.154.0"
            ),
        ]
        for (headers, expected) in cases {
            let transport = RecordingGatewayTransport(
                responses: [
                    response(status: .ok, body: Self.nativeCatalog),
                    response(status: .ok, body: compactionSummaryResponse()),
                ]
            )
            let responder = try makeResponder(transport: transport)
            _ = try await responder.recoverNativeCompaction(
                body: try request(),
                incomingHeaders: headers,
                eventID: UUID()
            )
            let discovery = try #require(await transport.requests.first)
            #expect(
                discovery.url
                    == "https://chatgpt.com/backend-api/codex/models?client_version=\(expected)"
            )
        }
    }
}
