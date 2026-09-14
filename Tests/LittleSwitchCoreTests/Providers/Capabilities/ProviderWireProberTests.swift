import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
// swift-format sorts case-sensitively ("NIO*" < "Network") while SwiftLint
// sorts case-insensitively; the two rules disagree only on this line.
// swiftlint:disable:next sorted_imports
import Network
import Testing

@testable import LittleSwitchCore

@Suite("Provider wire probe")
struct ProviderWireProberTests {
    @Test(
        "Empty-body statuses classify a route without spending tokens",
        arguments: [
            (UInt(200), ProviderWireAvailability.available),
            (UInt(204), ProviderWireAvailability.available),
            (UInt(302), ProviderWireAvailability.available),
            (UInt(400), ProviderWireAvailability.available),
            (UInt(422), ProviderWireAvailability.available),
            (UInt(404), ProviderWireAvailability.absent),
            (UInt(405), ProviderWireAvailability.absent),
            (UInt(401), ProviderWireAvailability.unknown),
            (UInt(402), ProviderWireAvailability.unknown),
            (UInt(403), ProviderWireAvailability.unknown),
            (UInt(429), ProviderWireAvailability.unknown),
            (UInt(500), ProviderWireAvailability.unknown),
            (UInt(503), ProviderWireAvailability.unknown),
        ])
    func statusClassification(status: UInt, expected: ProviderWireAvailability) {
        #expect(ProviderWireAvailability(status: status) == expected)
    }

    @Test("The probe classifies z.ai's real route matrix: messages and chat exist, responses does not")
    func probeClassifiesZAIRoutes() async throws {
        let providerID = try #require(
            UUID(uuidString: "057265e6-9c83-4f9d-92a4-93986f1e30e5")
        )
        let provider = Provider(
            id: providerID,
            name: "z.ai",
            baseURL: ProviderPreset.zai.baseURL,
            authMode: .bearer,
            anthropicBaseURL: ProviderPreset.zai.anthropicBaseURL
        )
        let transport = RecordingGatewayTransport(
            responses: [],
            routeStatuses: [
                "/v1/messages": 422,
                "/v1/responses": 404,
                "/chat/completions": 200,
            ]
        )
        let prober = ProviderWireProber(transport: transport)

        let probe = try await prober.probe(provider: provider, secret: "selected-secret")

        #expect(probe.messages == .available)
        #expect(probe.responses == .absent)
        #expect(probe.chatCompletions == .available)
        // Only an absent route is routing evidence; "available" is display
        // evidence — a lenient front door must never pin the native wire.

        let requests = await transport.requests
        #expect(requests.count == 3)
        // The chat probe must honor the z.ai endpoint split: Codex traffic on
        // the canonical preset goes to the coding endpoint, not the base URL.
        #expect(
            Set(requests.map(\.url))
                == Set([
                    "https://api.z.ai/api/anthropic/v1/messages",
                    "https://api.z.ai/api/coding/paas/v4/v1/responses",
                    "https://api.z.ai/api/coding/paas/v4/chat/completions",
                ])
        )
        for request in requests {
            #expect(request.body == Data("{}".utf8))
            #expect(request.headers["content-type"] == ["application/json"])
            #expect(request.headers["authorization"] == ["Bearer selected-secret"])
        }
    }

    @Test("A transport failure stays unknown and seeds nothing")
    func transportFailureStaysUnknown() async throws {
        let provider = Provider(
            name: "Firewalled",
            baseURL: "https://example.com/api",
            authMode: .bearer
        )
        let prober = ProviderWireProber(transport: FailingProbeTransport())

        let probe = try await prober.probe(provider: provider, secret: nil)

        #expect(probe.messages == .unknown)
        #expect(probe.responses == .unknown)
        #expect(probe.chatCompletions == .unknown)
    }

    @Test("Cancellation propagates instead of masquerading as an unknown verdict")
    func cancellationPropagates() async throws {
        let provider = Provider(
            name: "Slow",
            baseURL: "https://example.com/api",
            authMode: .bearer
        )
        let prober = ProviderWireProber(transport: CancellingGatewayTransport())

        await #expect(throws: CancellationError.self) {
            _ = try await prober.probe(provider: provider, secret: nil)
        }
    }

    @Test("The probe bound reaches the transport's per-request entry point")
    func probeBoundReachesPerRequestExecute() async throws {
        let provider = Provider(
            name: "Silent",
            baseURL: "https://example.com/api",
            authMode: .bearer
        )
        let transport = TimeoutRecordingProbeTransport()
        let prober = ProviderWireProber(transport: transport)

        _ = try await prober.probe(provider: provider, secret: nil)

        // The bound only protects the save if the per-request entry point
        // sees it through the protocol witness; an extension-only default
        // silently routes every transport back to its traffic-grade window.
        #expect(await transport.receivedTimeouts == [.seconds(8), .seconds(8), .seconds(8)])
    }

    @Test("A silent host is abandoned at the probe bound, not the transport default")
    func silentHostIsAbandonedAtProbeBound() async throws {
        let silentHost = try SilentHostListener()
        let port = try await eventually(
            timeout: .seconds(5),
            description: "the silent host to bind"
        ) { silentHost.port }
        let provider = Provider(
            name: "Silent",
            baseURL: "http://127.0.0.1:\(port)/api",
            authMode: .bearer
        )
        let transport = AsyncHTTPTransport()
        let prober = ProviderWireProber(transport: transport)

        let started = ContinuousClock.now
        var bounded: ProviderWireProbe?
        do {
            bounded = try await withAsyncTestTimeout(
                .seconds(30),
                description: "the silent-host probe to finish"
            ) {
                try await prober.probe(provider: provider, secret: nil)
            }
        } catch {
            silentHost.stop()
            try? await transport.shutdown()
            throw error
        }
        let elapsed = ContinuousClock.now - started
        silentHost.stop()
        let probe = try #require(bounded)

        #expect(probe.messages == .unknown)
        #expect(probe.responses == .unknown)
        #expect(probe.chatCompletions == .unknown)
        // The deadline must fire at the probe bound (8 s), far under the
        // transport's traffic-grade ten-minute default.
        #expect(elapsed >= .seconds(7))
        #expect(elapsed < .seconds(20))

        try await transport.shutdown()
    }
}

/// Accepts TCP connections and never answers — the silent-host shape the
/// probe bound exists for: a host that completes the handshake but never
/// writes a byte must be abandoned at the probe deadline, not held for the
/// transport's traffic-grade window. `NWListener` is documented thread-safe;
/// the connection list is guarded because accept callbacks arrive off the
/// test's isolation domain.
private final class SilentHostListener: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init() throws {
        let connectionQueue = DispatchQueue(label: "silent-host.connection")
        let listener = try NWListener(using: .tcp)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] (connection: NWConnection) in
            // Accepted and started, but never read from or written to.
            connection.start(queue: connectionQueue)
            self?.remember(connection)
        }
        listener.start(queue: DispatchQueue(label: "silent-host.listener"))
    }

    /// The assigned port, nil until the listener is actually listening
    /// (before ready, `port` still reports the requested wildcard `0`).
    var port: UInt16? {
        guard let raw = listener.port?.rawValue, raw != 0 else { return nil }
        return raw
    }

    /// Tears the listener and every accepted connection down so the probe's
    /// client-side sockets do not linger until the transport's shutdown.
    func stop() {
        lock.lock()
        let pending = connections
        connections.removeAll()
        lock.unlock()
        listener.cancel()
        for connection in pending {
            connection.cancel()
        }
    }

    private func remember(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
    }
}

private actor TimeoutRecordingProbeTransport: UpstreamTransport {
    private(set) var receivedTimeouts: [TimeAmount] = []

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        // The probe must not fall back to this unbounded entry point when
        // the transport can honor a per-request deadline.
        throw URLError(.timedOut)
    }

    func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse {
        receivedTimeouts.append(timeout)
        throw URLError(.timedOut)
    }
}

private struct FailingProbeTransport: UpstreamTransport {
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        throw URLError(.timedOut)
    }
}
