import AsyncHTTPClient
import NIOCore

public protocol UpstreamTransport: Sendable {
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse

    /// A per-request timeout cap for cheap, best-effort calls (the endpoint
    /// probe) that must not inherit the traffic-grade ten-minute window. A
    /// requirement so implementations that can bound a single exchange are
    /// reached through the protocol witness — an extension-only method
    /// never is, and the cap silently disappears.
    func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse

    func shutdown() async throws
}

extension UpstreamTransport {
    public func shutdown() async throws {}

    /// Fallback for transports without a per-request deadline of their own:
    /// their own default window is the only bound available.
    public func execute(
        _ request: HTTPClientRequest,
        timeout _: TimeAmount
    ) async throws -> HTTPClientResponse {
        try await execute(request)
    }
}
