import Foundation
import Hummingbird
import HummingbirdTLS
import Security
import ServiceLifecycle
import Testing

@testable import LittleSwitchCore

/// Positive HTTPS evidence for a test client with an in-memory authority.
/// The concrete OTLPHTTPTransport keeps macOS trust and has separate rejection tests.
@Suite("Monitoring outgoing HTTPS with a test-only trusted authority")
struct MonitoringOutgoingTLSTests {
    @Test("Encoded OTLP crosses verified HTTPS and receives an accepted response", arguments: MonitoringSignal.allCases)
    func accepted(signal: MonitoringSignal) async throws {
        let payload = try await makePayload(signal: signal)
        try await withReceiver(signal: signal) { port, identity, probe in
            let endpoint = try #require(URL(string: "https://localhost:\(port)/v1/\(signal.rawValue)"))
            let response = try await send(payload, to: endpoint, identity: identity, probe: probe)
            #expect(response.status == 200)
            #expect(response.body == Data("{}".utf8))
            #expect(OTLPExportResponse.parse(response, signal: signal) == .accepted)
            #expect(await probe.bodies == [payload])
            #expect(await probe.checks == [.init(hostname: "localhost", accepted: true)])
        }
    }

    @Test("A trusted authority does not authorize an IP absent from the certificate SAN")
    func wrongHostname() async throws {
        try await withReceiver(signal: .logs) { port, identity, probe in
            let endpoint = try #require(URL(string: "https://[::1]:\(port)/v1/logs"))
            await #expect(throws: URLError.self) {
                _ = try await send(Data("{}".utf8), to: endpoint, identity: identity, probe: probe)
            }
            #expect(await probe.checks == [.init(hostname: "::1", accepted: false)])
            #expect(await probe.bodies.isEmpty)
        }
    }

    private func makePayload(signal: MonitoringSignal) async throws -> Data {
        let date = Date(timeIntervalSince1970: 2)
        let store = MonitoringStore(resource: .init(serviceVersion: "tls-test", startedAt: date))
        let entry = await store.markTest(at: date)
        switch signal {
        case .metrics: return try OTLPMetricsEncoder.encode(await store.snapshot(at: date))
        case .logs: return try OTLPLogsEncoder.encode(resource: store.resource, entries: [entry])
        }
    }

    private func withReceiver(
        signal: MonitoringSignal,
        operation: @escaping @Sendable (Int, GatewayTLSIdentity, MonitoringTLSProbe) async throws -> Void
    ) async throws {
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let probe = MonitoringTLSProbe()
        let ready = AsyncThrowingStream<Int, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let router = Router()
        router.post(RouterPath("/v1/\(signal.rawValue)")) { request, _ in
            #expect(request.headers[.contentType] == "application/json")
            #expect(request.headers[.accept] == "application/json")
            let body = try await request.body.collect(upTo: 524_288)
            await probe.received(Data(body.readableBytesView))
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{}")))
        }
        // The existing identity covers localhost and 127.0.0.1, but not ::1.
        let application = try Application(
            router: router,
            server: .tls(.http1(), tlsConfiguration: identity.tlsConfiguration),
            configuration: .init(address: .hostname("::1", port: 0))
        ) { channel in
            if let port = channel.localAddress?.port { ready.continuation.yield(port) }
            ready.continuation.finish()
        }
        let services = ServiceGroup(configuration: .init(services: [application], logger: application.logger))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    try await services.run()
                    ready.continuation.finish()
                } catch {
                    ready.continuation.finish(throwing: error)
                    throw error
                }
            }
            do {
                var ports = ready.stream.makeAsyncIterator()
                let port = try #require(await ports.next())
                try await operation(port, identity, probe)
                await services.triggerGracefulShutdown()
                try await group.waitForAll()
            } catch {
                await services.triggerGracefulShutdown()
                group.cancelAll()
                try? await group.waitForAll()
                throw error
            }
        }
    }

    private func send(
        _ body: Data,
        to endpoint: URL,
        identity: GatewayTLSIdentity,
        probe: MonitoringTLSProbe
    ) async throws -> OTLPHTTPResponse {
        let authority = Data(try identity.authority.toDERBytes())
        let invalidated = AsyncStream<Void>.makeStream()
        let delegate = MonitoringTLSClientDelegate(
            authority: authority, probe: probe, invalidated: invalidated.continuation)
        let session = URLSession(
            configuration: OTLPHTTPTransport.sessionConfiguration(), delegate: delegate, delegateQueue: nil)
        // This owned task also joins invalidation when the requesting task is cancelled.
        let invalidation = Task {
            var events = invalidated.stream.makeAsyncIterator()
            _ = await events.next()
        }
        let result: Result<OTLPHTTPResponse, any Error>
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            let http = try #require(response as? HTTPURLResponse)
            result = .success(
                .init(
                    status: http.statusCode,
                    contentType: http.value(forHTTPHeaderField: "Content-Type"),
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
                    body: data))
        } catch {
            result = .failure(error)
        }
        session.invalidateAndCancel()
        await invalidation.value
        return try result.get()
    }
}

private actor MonitoringTLSProbe {
    struct Check: Equatable, Sendable {
        let hostname: String
        let accepted: Bool
    }

    private(set) var bodies: [Data] = []
    private(set) var checks: [Check] = []

    func received(_ body: Data) { bodies.append(body) }
    func checked(hostname: String, accepted: Bool) { checks.append(.init(hostname: hostname, accepted: accepted)) }
}

private final class MonitoringTLSClientDelegate: NSObject, URLSessionDelegate {
    private let authority: Data
    private let probe: MonitoringTLSProbe
    private let invalidated: AsyncStream<Void>.Continuation

    init(authority: Data, probe: MonitoringTLSProbe, invalidated: AsyncStream<Void>.Continuation) {
        self.authority = authority
        self.probe = probe
        self.invalidated = invalidated
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            let certificate = SecCertificateCreateWithData(nil, authority as CFData)
        else { return (.performDefaultHandling, nil) }
        let hostname = challenge.protectionSpace.host
        let configured =
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, hostname as CFString)) == errSecSuccess
            && SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess
            && SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess
            && SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess
        let accepted = configured && SecTrustEvaluateWithError(trust, nil)
        await probe.checked(hostname: hostname, accepted: accepted)
        return accepted ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        invalidated.finish()
    }
}
