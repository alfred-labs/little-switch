import Foundation

public struct TrafficUpstreamRequest: Codable, Equatable, Sendable {
    public var attempt: Int
    public var claudeRoute: String
    public var providerID: UUID
    public var providerName: String
    public var modelID: String
    public var url: String
    public var headers: [TrafficHeader]
    public var body: Data
    public var streaming: Bool

    public init(
        attempt: Int,
        claudeRoute: String,
        providerID: UUID,
        providerName: String,
        modelID: String,
        url: String,
        headers: [TrafficHeader],
        body: Data,
        streaming: Bool
    ) {
        self.attempt = attempt
        self.claudeRoute = claudeRoute
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.url = url
        self.headers = headers
        self.body = body
        self.streaming = streaming
    }
}
