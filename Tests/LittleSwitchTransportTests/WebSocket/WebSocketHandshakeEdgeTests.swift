import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketHandshakeEdgeTests {
    @Test func aRedirectRemainsARejection() async throws {
        let failure = try await rejected(
            reply: .init(
                status: .temporaryRedirect,
                headers: ["Location": "http://127.0.0.1:1/must-not-follow", "Retry-After": "7"]))
        #expect(failure.kind == .upgradeRejected)
        let response = try #require(failure.response)
        #expect(response.head.status == .temporaryRedirect)
        #expect(response.head.headers["Location"] == ["http://127.0.0.1:1/must-not-follow"])
        #expect(response.head.headers["Retry-After"] == ["7"])
        #expect(response.bodyState == .complete)
    }

    @Test func preservesARejectedHeadWhenTheBodyEndsEarly() async throws {
        let failure = try await rejected(
            reply: .init(
                status: .unauthorized,
                headers: ["Content-Length": "100", "Retry-After": "5"],
                body: Data("partial".utf8),
                finish: false,
                closeAfterBody: true))
        #expect(failure.kind == .upgradeRejected)
        let response = try #require(failure.response)
        #expect(response.head.status == .unauthorized)
        #expect(response.head.headers["Retry-After"] == ["5"])
        #expect(response.bodyPrefix == Data("partial".utf8))
        #expect(response.bodyState == .invalidHTTP || response.bodyState == .connectionClosed)
    }

    @Test func reportsInvalidUpgradeWithIts101Headers() async throws {
        let failure = try await rejected(
            reply: .init(
                status: .switchingProtocols,
                headers: [
                    "Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Accept": "invalid",
                    "X-Trace": "keep",
                ]))
        #expect(failure.kind == .invalidUpgrade)
        let response = try #require(failure.response)
        #expect(response.head.status == .switchingProtocols)
        #expect(response.head.headers["X-Trace"] == ["keep"])
    }

    @Test func boundsAnUnfinishedHandshakeWithoutInventingAResponse() async throws {
        let failure = try await rejected(
            reply: .init(sendHead: false), configuration: .init(handshakeTimeout: .milliseconds(50)))
        #expect(failure.kind == .handshakeTimedOut)
        #expect(failure.response == nil)
    }

    @Test func boundsTheHeadersBeforeTheyCanBecomeAResponseSnapshot() async throws {
        let failure = try await rejected(
            reply: .init(headers: ["X-Large": String(repeating: "x", count: 256)]),
            configuration: .init(maximumHeaderFieldBytes: 64))
        #expect(failure.response == nil)
        #expect(failure.kind == .connectionFailed)
    }

    @Test func errorDescriptionsNeverIncludeHTTPContent() {
        let response = UpstreamWebSocketHTTPResponse(
            head: .init(version: .http1_1, status: .unauthorized, headers: ["X-Secret": "synthetic-secret"]),
            bodyPrefix: Data("synthetic-body".utf8),
            bodyState: .complete)
        let error = UpstreamWebSocketFailure(kind: .upgradeRejected, response: response)
        let send = UpstreamWebSocketSendFailure(submission: .notSubmitted, cause: error)
        #expect(error.description == "WebSocket failure: upgradeRejected")
        #expect(send.description == "WebSocket failure: upgradeRejected (notSubmitted)")
    }

    private func rejected(
        reply: WebSocketHTTPTestServer.Reply,
        configuration: UpstreamWebSocketConfiguration = .init()
    ) async throws -> UpstreamWebSocketFailure {
        let server = try await WebSocketHTTPTestServer.start(reply: reply)
        let transport = try NIOUpstreamWebSocketTransport(configuration: configuration)
        do {
            let url = try #require(URL(string: "ws://127.0.0.1:\(server.port)"))
            let failure: UpstreamWebSocketFailure
            do {
                try await transport.withConnection(UpstreamWebSocketRequest(url: url)) { _ in
                    Issue.record("An invalid or rejected handshake entered the operation")
                }
                throw MissingExpectedHandshakeFailure()
            } catch let error as UpstreamWebSocketFailure {
                failure = error
            }
            try await transport.shutdown()
            try await server.stop()
            return failure
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }
}

private struct MissingExpectedHandshakeFailure: Error {}
