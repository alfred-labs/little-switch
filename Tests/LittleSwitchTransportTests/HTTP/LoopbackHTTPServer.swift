import Foundation
import Network

/// A minimal TCP server that responds to the first HTTP request with a
/// preconfigured status, content type and body, then closes. Enough to
/// exercise a real loopback HTTP round-trip without importing Hummingbird.
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
                    if case .ready = state { self.respond(connection) }
                }
                connection.start(queue: .global())
            }
            listener.start(queue: .global())
        }
    }

    func stop() async {
        listener.cancel()
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
