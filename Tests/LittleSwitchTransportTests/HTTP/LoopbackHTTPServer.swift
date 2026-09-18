import Foundation
import Network

/// A minimal TCP server that responds to the first HTTP request with a
/// preconfigured status, content type and body, then closes. Requests are
/// expected to be bodyless (the current client sends a GET); the server answers
/// once the request-head terminator arrives. Enough to exercise a real loopback
/// HTTP round-trip without importing Hummingbird.
final class LoopbackHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let statusCode: Int
    private let contentType: String
    private let body: Data
    private(set) var port: UInt16?

    init(statusCode: Int, contentType: String, body: Data) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let ready = continuation
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = self.listener.port?.rawValue { self.port = port }
                    ready.resume()
                case .failed(let error):
                    ready.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: self.awaitRequest(connection)
                    // Under heavy instrumentation load NW may park a fresh
                    // connection in a waiting state; restart it instead of
                    // letting it fail as a reset.
                    case .waiting: connection.restart()
                    default: break
                    }
                }
                connection.start(queue: .global())
            }
            listener.start(queue: .global())
        }
    }

    func stop() async {
        listener.cancel()
    }

    /// Read the request head before answering: responding and closing an
    /// unread connection can reset a client whose request is still in
    /// flight, which surfaced as ECONNRESET under Thread Sanitizer timing.
    private func awaitRequest(_ connection: NWConnection) {
        receiveHead(connection, accumulated: [])
    }

    private func receiveHead(_ connection: NWConnection, accumulated: [UInt8]) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] data, _, isComplete, error in
            var received = accumulated
            if let data { received.append(contentsOf: data) }
            if Self.hasRequestTerminator(received) {
                respond(connection)
            } else if error == nil, !isComplete {
                receiveHead(connection, accumulated: received)
            } else {
                connection.cancel()
            }
        }
    }

    private static let requestTerminator = [0x0D, 0x0A, 0x0D, 0x0A]

    private static func hasRequestTerminator(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= requestTerminator.count else { return false }
        for start in 0...(bytes.count - requestTerminator.count)
        where (0..<requestTerminator.count).allSatisfy({ bytes[start + $0] == requestTerminator[$0] }) {
            return true
        }
        return false
    }

    private func respond(_ connection: NWConnection) {
        let head =
            "HTTP/1.1 \(statusCode) OK\r\nContent-Type: \(contentType)\r\nContent-Encoding: gzip\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let response = Data(head.utf8) + body
        connection.send(
            content: response,
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }
}
