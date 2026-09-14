import Foundation

public struct CodexModelTarget: Equatable, Identifiable, Sendable {
    public var provider: Provider
    public var model: DiscoveredModel

    public init(provider: Provider, model: DiscoveredModel) {
        self.provider = provider
        self.model = model
    }

    public var id: String {
        "\(provider.id.uuidString.lowercased())|\(model.id)"
    }

    public var mapping: ModelMapping {
        ModelMapping(providerID: provider.id, modelID: model.id)
    }

    public var displayName: String {
        "\(provider.name)/\(model.id)"
    }
}
