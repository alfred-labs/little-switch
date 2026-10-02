import Foundation

public protocol UpstreamWebSocketTransport: Sendable {
    /// Opens one connection and invokes the operation once after a verified upgrade.
    /// Handles are valid only during the operation. A normal return closes gracefully;
    /// failure or cancellation aborts and joins I/O before returning. No retries occur.
    /// Operations and callbacks must cooperate with cancellation and join their children.
    func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws
    /// Rejects new work, aborts active connections, and waits for their scope cleanup.
    /// Idempotent. Calling from an operation owned by this transport fails to avoid joining itself.
    func shutdown() async throws
}

public struct UpstreamWebSocketConnection: Sendable {
    public let inbound: any UpstreamWebSocketInbound
    public let outbound: any UpstreamWebSocketOutbound
    package private(set) var diagnostics: @Sendable () async -> UpstreamWebSocketDiagnostics?

    public init(inbound: any UpstreamWebSocketInbound, outbound: any UpstreamWebSocketOutbound) {
        self.inbound = inbound
        self.outbound = outbound
        self.diagnostics = { nil }
    }

    package init(
        inbound: any UpstreamWebSocketInbound,
        outbound: any UpstreamWebSocketOutbound,
        diagnostics: @escaping @Sendable () async -> UpstreamWebSocketDiagnostics?
    ) {
        self.init(inbound: inbound, outbound: outbound)
        self.diagnostics = diagnostics
    }
}

public protocol UpstreamWebSocketInbound: Sendable {
    /// Claims the connection's only consumer. Every subsequent invocation fails.
    /// Callbacks run sequentially and apply backpressure until they return.
    func consume(
        _ onMessage: @escaping @Sendable (UpstreamWebSocketMessage) async throws -> Void
    ) async throws -> UpstreamWebSocketPeerClose
}

public protocol UpstreamWebSocketOutbound: Sendable {
    /// Serializes complete messages, including their fragments. Success proves local
    /// writing, not peer acceptance. Every failure carries the possible submission state.
    func send(_ message: UpstreamWebSocketMessage) async throws
    /// Orders a close after accepted messages and rejects subsequent sends. Returns
    /// after local writing; scope cleanup waits for the peer within the close deadline.
    func close(code: UInt16, reason: String?) async throws
}

extension UpstreamWebSocketOutbound {
    public func close() async throws { try await close(code: 1_000, reason: nil) }
}

public enum UpstreamWebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// The peer's close code. Its reason text is validated on the wire but not retained.
public struct UpstreamWebSocketPeerClose: Sendable, Equatable {
    /// An empty close frame has no code.
    public let code: UInt16?

    public init(code: UInt16?) {
        self.code = code
    }
}
