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

public struct CodexConfiguration: Codable, Equatable, Sendable {
    public var connected: Bool
    public var defaultModel: ModelMapping?
    public var excludedModels: [ModelMapping]
    public var autoReviewModel: ModelMapping?

    public static let disconnected = CodexConfiguration()

    public init(
        connected: Bool = false,
        defaultModel: ModelMapping? = nil,
        excludedModels: [ModelMapping] = [],
        autoReviewModel: ModelMapping? = nil
    ) {
        self.connected = connected
        self.defaultModel = defaultModel
        self.excludedModels = excludedModels
        self.autoReviewModel = autoReviewModel
    }

    public func availableModels(in providers: [Provider]) -> [CodexModelTarget] {
        providers
            .flatMap { provider in
                provider.models.map { CodexModelTarget(provider: provider, model: $0) }
            }
            .sorted(by: Self.precedes)
    }

    public func exposedModels(in providers: [Provider]) -> [CodexModelTarget] {
        let excluded = Set(excludedModels)
        return availableModels(in: providers).filter { !excluded.contains($0.mapping) }
    }

    public func resolvedDefaultModel(in providers: [Provider]) -> ModelMapping? {
        let exposed = exposedModels(in: providers)
        if let defaultModel, exposed.contains(where: { $0.mapping == defaultModel }) {
            return defaultModel
        }
        return exposed.first?.mapping
    }

    public func normalized(for providers: [Provider]) -> CodexConfiguration {
        var result = self
        result.excludedModels = Array(Set(excludedModels)).sorted(by: Self.precedes)
        result.defaultModel = result.resolvedDefaultModel(in: providers)
        return result
    }

    public func resolvedAutoReviewTarget(in providers: [Provider]) -> CodexModelTarget? {
        // A chosen reviewer is independent of task-model exposure. Keep an
        // unavailable explicit choice unresolved instead of switching reviewers.
        let mapping = autoReviewModel ?? resolvedDefaultModel(in: providers)
        return availableModels(in: providers).first { $0.mapping == mapping }
    }

    private static func precedes(_ left: CodexModelTarget, _ right: CodexModelTarget) -> Bool {
        let comparison = left.displayName.compare(
            right.displayName,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return precedes(left.mapping, right.mapping)
    }

    private static func precedes(_ left: ModelMapping, _ right: ModelMapping) -> Bool {
        let leftKey = "\(left.providerID.uuidString.lowercased())|\(left.modelID)"
        let rightKey = "\(right.providerID.uuidString.lowercased())|\(right.modelID)"
        return leftKey < rightKey
    }
}
