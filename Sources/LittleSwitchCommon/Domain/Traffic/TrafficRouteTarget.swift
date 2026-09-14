import Foundation

public struct TrafficRouteTarget: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var providerName: String
    public var modelID: String

    public init(providerID: UUID, providerName: String, modelID: String) {
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
    }
}
