import Foundation
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketNestedOwnershipTests {
    @Test func nestedConnectionsKeepEveryOwningTransportInTheShutdownGuard() async throws {
        let server = try await WebSocketTestServer.start()
        let outer = try NIOUpstreamWebSocketTransport()
        let inner = try NIOUpstreamWebSocketTransport()
        let attempt = WebSocketShutdownAttempt()
        do {
            let request = try UpstreamWebSocketRequest(url: #require(URL(string: "ws://127.0.0.1:\(server.port)")))
            do {
                try await outer.withConnection(request) { _ in
                    try await inner.withConnection(request) { _ in
                        // Intentionally inherit both operation contexts. Joining this task
                        // after the scopes end also keeps the regression's failure bounded.
                        let task = Task { () -> UpstreamWebSocketFailure.Kind? in
                            do {
                                try await outer.shutdown()
                                return nil
                            } catch let failure as UpstreamWebSocketFailure {
                                return failure.kind
                            } catch {
                                return .connectionFailed
                            }
                        }
                        await attempt.set(task)
                        try await Task.sleep(for: .milliseconds(30))
                    }
                }
            } catch {
                Issue.record("Nested shutdown unexpectedly aborted an operation: \(type(of: error))")
            }
            let task = try #require(await attempt.task)
            #expect(await task.value == .shutdownFromConnection)
            try await outer.shutdown()
            try await inner.shutdown()
            try await server.stop()
        } catch {
            try? await outer.shutdown()
            try? await inner.shutdown()
            try? await server.stop()
            throw error
        }
    }
}

private actor WebSocketShutdownAttempt {
    private(set) var task: Task<UpstreamWebSocketFailure.Kind?, Never>?
    func set(_ task: Task<UpstreamWebSocketFailure.Kind?, Never>) { self.task = task }
}
