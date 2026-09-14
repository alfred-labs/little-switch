import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

/// Probes a provider's endpoint routes at save time with zero-token requests.
///
/// A POST carrying an empty JSON object is rejected by schema validation on
/// every existing route — the model never runs, so nothing is billed — while
/// a missing route answers 404. Verified live against z.ai (FastAPI: 422 for
/// `/v1/messages`, `404 {"detail":"Not Found"}` for `/v1/responses`) and a
/// second inference gateway (400 on all three routes). Statuses a firewall,
/// auth wall, or quota can produce (401/402/403/429/5xx) say nothing about
/// the route itself and stay unknown, leaving prior routing evidence
/// untouched.
public struct ProviderWireProber: ProviderWireProbing {
    /// Probes are best-effort evidence for a settings sheet, never worth a
    /// traffic-grade wait: a host that accepts TCP but never answers must
    /// not hold a save hostage for two full minutes.
    private static let probeTimeout = TimeAmount.seconds(8)

    private let transport: any UpstreamTransport

    public init(transport: any UpstreamTransport) {
        self.transport = transport
    }

    /// Probes the three routes concurrently. Throws only on cancellation —
    /// every other failure is an `.unknown` verdict, because a probe must
    /// not fail a save; a cancelled save must not continue as if it ran.
    public func probe(provider: Provider, secret: String?) async throws -> ProviderWireProbe {
        async let messages = probedAvailability(.messages, provider: provider, secret: secret)
        async let responses = probedAvailability(.responses, provider: provider, secret: secret)
        async let chatCompletions =
            probedAvailability(.chatCompletions, provider: provider, secret: secret)
        return try await ProviderWireProbe(
            messages: messages,
            responses: responses,
            chatCompletions: chatCompletions,
            date: Date()
        )
    }

    /// The request is built inside so an invalid base URL is just another
    /// `.unknown`, not a thrown error the save would have to handle.
    private func probedAvailability(
        _ api: ProviderEndpoint.ForwardingAPI,
        provider: Provider,
        secret: String?
    ) async throws -> ProviderWireAvailability {
        do {
            let request = try ProviderRequestBuilder.forwarding(
                api: api,
                provider: provider,
                secret: secret,
                headers: HTTPHeaders([("content-type", "application/json")]),
                body: Data("{}".utf8)
            )
            let response = try await transport.execute(
                request,
                timeout: Self.probeTimeout
            )
            // Consume the small error body so the connection returns to the
            // pool; its content is irrelevant to the verdict.
            _ = try? await response.body.collect(upTo: 16 * 1_024)
            return ProviderWireAvailability(status: UInt(response.status.code))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unknown
        }
    }
}
