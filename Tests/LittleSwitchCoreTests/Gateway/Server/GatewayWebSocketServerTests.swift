import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchTransport
import LittleSwitchWire
import Security
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("The Responses listener upgrades a WebSocket and answers its ping")
    func responsesWebSocketListenerAcceptsHandshakeAndPing() async throws {
        let fixture = try makeFixture()
        let (server, port) = try await Self.startWebSocketTestServer(fixture: fixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/responses"))
        let socket = session.webSocketTask(with: url)
        socket.resume()
        do {
            try await webSocketPing(socket)
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            await server.stop()
            throw error
        }
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        await server.stop()
        #expect(await !server.isRunning)
    }

    @Test("Stopping the gateway closes an idle upgraded connection")
    func responsesWebSocketStopClosesSession() async throws {
        let fixture = try makeFixture()
        let (server, port) = try await Self.startWebSocketTestServer(fixture: fixture)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/responses"))
        let socket = session.webSocketTask(with: url)
        socket.resume()
        do {
            try await webSocketPing(socket)
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            await server.stop()
            throw error
        }
        await server.stop()
        await #expect(throws: (any Error).self) {
            try await webSocketPing(socket)
        }
        socket.cancel(with: .goingAway, reason: nil)
        #expect(await !server.isRunning)
    }

    @Test("The WebSocket endpoint rejects browser Origin handshakes")
    func responsesWebSocketListenerRejectsOrigin() async throws {
        let fixture = try makeFixture()
        let app = try makeWebSocketApplication(fixture: fixture)
        try await app.test(.live) { client in
            let port = try #require(client.port)
            let url = try #require(URL(string: "ws://localhost:\(port)/v1/responses"))
            var request = URLRequest(url: url)
            request.setValue("https://example.com", forHTTPHeaderField: "Origin")
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let socket = session.webSocketTask(with: request)
            socket.resume()
            await #expect(throws: (any Error).self) {
                try await webSocketPing(socket)
            }
            #expect((socket.response as? HTTPURLResponse)?.statusCode == 400)
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    @Test("The shared listener exchanges WSS JSON and ordinary HTTP on its ephemeral port")
    func responsesWebSocketTLSAndHTTPShareListener() async throws {
        let fixture = try makeFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let app = try makeWebSocketApplication(fixture: fixture, tlsIdentity: identity)
        let trust = GatewayWebSocketTestTrust(authorityDER: Data(try identity.authority.toDERBytes()))
        try await app.test(.ahc()) { client in
            let port = try #require(client.port)
            let url = try #require(URL(string: "wss://localhost:\(port)/v1/responses"))
            let session = URLSession(configuration: .ephemeral, delegate: trust, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let socket = session.webSocketTask(with: url)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }
            try await socket.send(.string("{}"))
            let message = try await socket.receive()
            guard case .string(let text) = message else {
                Issue.record("Expected a JSON error message over WSS")
                return
            }
            let error = try #require(JSONValue.parse(Data(text.utf8)).object)
            #expect(error["type"] == .string("error"))
            let response = try await client.execute(uri: "/api/about", method: .get)
            #expect(response.status == .ok)
        }
    }

    @Test("Binary input closes the Responses WebSocket with unsupported-data status")
    func responsesWebSocketRejectsBinaryInput() async throws {
        let fixture = try makeFixture()
        let app = try makeWebSocketApplication(fixture: fixture)
        try await app.test(.live) { client in
            let port = try #require(client.port)
            try await expectWebSocketClose(port: port, message: .data(Data("{}".utf8)), code: .unsupportedData)
        }
    }

    @Test("Oversized frames close the Responses WebSocket before request execution")
    func responsesWebSocketRejectsOversizedFrame() async throws {
        let fixture = try makeFixture()
        var limits = ResponsesWebSocketLimits()
        limits.maxFrameBytes = 16
        let app = try makeWebSocketApplication(fixture: fixture, limits: limits)
        try await app.test(.live) { client in
            let port = try #require(client.port)
            try await expectWebSocketClose(
                port: port,
                message: .string(String(repeating: "x", count: 17)),
                code: .messageTooBig
            )
        }
    }

    private static func startWebSocketTestServer(
        fixture: GatewayFixture
    ) async throws -> (GatewayServer, Int) {
        var lastError: (any Error)?
        for _ in 0..<5 {
            let port = Int.random(in: 30_000...60_000)
            let server = GatewayServer(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                listenPort: port,
                requiredAuthorityPort: port
            )
            do {
                try await server.start()
                return (server, port)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GatewayServer.Error.stoppedBeforeReady
    }

    func makeWebSocketApplication(
        fixture: GatewayFixture,
        transport: (any UpstreamTransport)? = nil,
        tlsIdentity: GatewayTLSIdentity? = nil,
        limits: ResponsesWebSocketLimits = .init()
    ) throws -> Application<GatewayResponder> {
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport ?? RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        return Application(
            responder: responder,
            server: try GatewayWebSocketServer.make(
                responder: responder,
                requiredAuthorityPort: nil,
                tlsConfiguration: tlsIdentity?.tlsConfiguration,
                limits: limits
            )
        )
    }
}

private func webSocketPing(_ socket: URLSessionWebSocketTask) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        socket.sendPing { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

private func expectWebSocketClose(
    port: Int,
    message: URLSessionWebSocketTask.Message,
    code: URLSessionWebSocketTask.CloseCode
) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 5
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let url = try #require(URL(string: "ws://localhost:\(port)/v1/responses"))
    let socket = session.webSocketTask(with: url)
    socket.resume()
    defer { socket.cancel(with: .normalClosure, reason: nil) }
    try await socket.send(message)
    await #expect(throws: (any Error).self) {
        _ = try await socket.receive()
    }
    #expect(socket.closeCode == code)
}

private final class GatewayWebSocketTestTrust: NSObject, URLSessionDelegate, Sendable {
    let authorityDER: Data

    init(authorityDER: Data) {
        self.authorityDER = authorityDER
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            let authority = SecCertificateCreateWithData(nil, authorityDER as CFData),
            SecTrustSetAnchorCertificates(trust, [authority] as CFArray) == errSecSuccess,
            SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
            SecTrustEvaluateWithError(trust, nil)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
