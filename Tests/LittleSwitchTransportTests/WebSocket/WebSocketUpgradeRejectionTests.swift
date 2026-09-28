import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

struct WebSocketUpgradeRejectionTests {
    @Test func retainsStatusDuplicateHeadersAndBody() async throws {
        let server = try await WebSocketHTTPTestServer.start(
            reply: .init(
                headers: HTTPHeaders([("Retry-After", "12"), ("Retry-After", "24"), ("X-Request-ID", "fixture")]),
                body: Data("limited".utf8)))
        let transport = try NIOUpstreamWebSocketTransport()
        do {
            let failure = try await rejected(transport, port: server.port)
            #expect(failure.kind == .upgradeRejected)
            let response = try #require(failure.response)
            #expect(response.head.status == .tooManyRequests)
            #expect(response.head.headers["Retry-After"] == ["12", "24"])
            #expect(response.head.headers["X-Request-ID"] == ["fixture"])
            #expect(response.bodyPrefix == Data("limited".utf8))
            #expect(response.bodyState == .complete)
            let request = try await server.request()
            #expect(request.method == .GET)
            #expect(request.uri == "/a%2Fb?value=a%2Bb")
            #expect(!request.headers.contains(name: "Origin"))
            #expect(request.headers["X-Turn"] == ["one", "two"])
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func capsRejectedBodyWithoutLosingHTTPMetadata() async throws {
        let server = try await WebSocketHTTPTestServer.start(
            reply: .init(
                headers: ["Retry-After": "17"], body: Data("0123456789".utf8)))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(maximumRejectionBodyBytes: 4))
        do {
            let failure = try await rejected(transport, port: server.port)
            #expect(failure.kind == .upgradeRejected)
            let response = try #require(failure.response)
            #expect(response.head.headers["Retry-After"] == ["17"])
            #expect(response.bodyPrefix == Data("0123".utf8))
            #expect(response.bodyState == .limitReached)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func preservesRejectionWhenBodyStalls() async throws {
        let server = try await WebSocketHTTPTestServer.start(
            reply: .init(
                headers: ["Retry-After": "5", "Content-Length": "100"], body: Data("part".utf8), finish: false))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(rejectionBodyTimeout: .milliseconds(40)))
        do {
            let failure = try await rejected(transport, port: server.port)
            #expect(failure.kind == .upgradeRejected)
            let response = try #require(failure.response)
            #expect(response.head.status == .tooManyRequests)
            #expect(response.bodyPrefix == Data("part".utf8))
            #expect(response.bodyState == .deadlineExpired)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    private func rejected(
        _ transport: NIOUpstreamWebSocketTransport, port: Int
    ) async throws -> UpstreamWebSocketFailure {
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/a%2Fb?value=a%2Bb"))
        let request = try UpstreamWebSocketRequest(
            url: url, headers: HTTPHeaders([("X-Turn", "one"), ("X-Turn", "two")]))
        do {
            try await transport.withConnection(request) { _ in
                Issue.record("A rejected upgrade must not invoke the connection operation")
            }
            throw MissingRejection()
        } catch let failure as UpstreamWebSocketFailure {
            return failure
        }
    }
}

private struct MissingRejection: Error {}
