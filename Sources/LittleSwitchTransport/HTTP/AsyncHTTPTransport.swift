import AsyncHTTPClient
import NIOCore

public final class AsyncHTTPTransport: UpstreamTransport, @unchecked Sendable {
    /// The traffic-grade window every production transport inherits when
    /// constructed without an explicit timeout.
    public static let defaultTimeout: TimeAmount = .seconds(120)

    private let client: HTTPClient
    private let timeout: TimeAmount

    public init(timeout: TimeAmount = AsyncHTTPTransport.defaultTimeout) {
        let configuration = Self.httpClientConfiguration()
        self.client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
        self.timeout = timeout
    }

    package static func httpClientConfiguration() -> HTTPClient.Configuration {
        var configuration = HTTPClient.Configuration()
        configuration.proxy = nil
        configuration.decompression = .enabled(limit: .ratio(25))
        return configuration
    }

    public func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        try await client.execute(request, timeout: timeout)
    }

    public func execute(
        _ request: HTTPClientRequest,
        timeout perRequest: TimeAmount
    ) async throws -> HTTPClientResponse {
        try await client.execute(request, timeout: perRequest)
    }

    public func shutdown() async throws {
        try await client.shutdown()
    }
}
