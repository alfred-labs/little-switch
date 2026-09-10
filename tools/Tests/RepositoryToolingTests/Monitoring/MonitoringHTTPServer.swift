import Foundation
import Network
import Testing

actor MonitoringHTTPServer {
    enum Reply: Sendable {
        case http(status: Int, headers: [String: String] = [:], body: String = "")
        case wait
    }

    enum Failure: Error { case noRequest }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "MonitoringHTTPFixture")
    private let reply: Reply
    private var startup: CheckedContinuation<Void, any Error>?
    private var connections: [NWConnection] = []
    private var pending: [ObjectIdentifier: Data] = [:]
    private(set) var requests: [Data] = []

    private init(reply: Reply) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        self.reply = reply
    }

    static func withServer(
        reply: Reply, body: @Sendable (MonitoringHTTPServer) async throws -> Void
    ) async throws {
        let server = try MonitoringHTTPServer(reply: reply)
        do {
            try await server.start()
            try await body(server)
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func endpoint() throws -> URL {
        let port = try #require(listener.port?.rawValue)
        return try URL("http://127.0.0.1:\(port)/fixture", strategy: .url)
    }

    func waitUntilRequest() async throws {
        for _ in 0..<100 {
            if !requests.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.noRequest
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            listener.stateUpdateHandler = { state in Task { await self.stateChanged(state) } }
            listener.newConnectionHandler = { connection in Task { await self.accept(connection) } }
            listener.start(queue: queue)
        }
    }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            startup?.resume()
            startup = nil
        case .failed(let error):
            startup?.resume(throwing: error)
            startup = nil
        default: break
        }
    }

    private func stop() {
        listener.cancel()
        for connection in connections { connection.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(connection)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { bytes, _, complete, error in
            Task { await self.received(bytes, complete: complete, failed: error != nil, from: connection) }
        }
    }

    private func received(_ bytes: Data?, complete: Bool, failed: Bool, from connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        if let bytes { pending[key, default: Data()].append(bytes) }
        let data = pending[key, default: Data()]
        if let boundary = data.range(of: Data("\r\n\r\n".utf8)) {
            let headers = String(data: data[..<boundary.lowerBound], encoding: .utf8) ?? ""
            let headerLine = headers.components(separatedBy: "\r\n").first {
                $0.lowercased().hasPrefix("content-length:")
            }
            let parsed = headerLine.flatMap {
                Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
            }
            let length = parsed ?? 0
            if data.count >= boundary.upperBound + length {
                requests.append(data)
                pending[key] = nil
                respond(connection)
                return
            }
        }
        if complete || failed { return }
        receive(connection)
    }

    private func respond(_ connection: NWConnection) {
        // swiftlint:disable:next pattern_matching_keywords
        guard case .http(let status, let headers, let body) = reply else { return }
        let fields = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined()
        let response =
            "HTTP/1.1 \(status) Fixture\r\n\(fields)Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
