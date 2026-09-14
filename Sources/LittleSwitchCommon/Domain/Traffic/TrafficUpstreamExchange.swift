import Foundation

public struct TrafficUpstreamExchange: Codable, Equatable, Sendable, Identifiable {
    public var attempt: Int
    public var request: TrafficUpstreamRequest?
    public var responseStatus: Int?
    public var response: TrafficPayload

    public var id: Int { attempt }

    public init(
        attempt: Int,
        request: TrafficUpstreamRequest? = nil,
        responseStatus: Int? = nil,
        response: TrafficPayload = TrafficPayload()
    ) {
        self.attempt = attempt
        self.request = request
        self.responseStatus = responseStatus
        self.response = response
    }
}
