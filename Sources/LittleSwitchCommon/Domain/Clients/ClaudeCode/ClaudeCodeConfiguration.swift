import Foundation

public enum ClaudeCodeContextMode: String, Codable, Hashable, Sendable {
    case standard
    case extended1M = "1m"
}

public struct ClaudeCodeConfiguration: Codable, Equatable, Sendable {
    public var connected: Bool
    public var defaultModel: String?
    public var contextMode: ClaudeCodeContextMode

    public static let disconnected = ClaudeCodeConfiguration()

    public init(
        connected: Bool = false,
        defaultModel: String? = nil,
        contextMode: ClaudeCodeContextMode = .standard
    ) {
        self.connected = connected
        self.defaultModel = defaultModel
        self.contextMode = contextMode
    }

    private enum CodingKeys: String, CodingKey {
        case connected
        case defaultModel
        case contextMode
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        connected = try values.decode(Bool.self, forKey: .connected)
        defaultModel = try values.decodeIfPresent(String.self, forKey: .defaultModel)
        contextMode =
            try values.decodeIfPresent(
                ClaudeCodeContextMode.self,
                forKey: .contextMode
            ) ?? .standard
    }

    public func mappedRouteIDs(
        providers: [Provider],
        mappings: [String: ModelMapping]
    ) -> [String] {
        ClaudeRoute.all.compactMap { route in
            guard let mapping = mappings[route.id],
                providers.contains(where: { provider in
                    provider.id == mapping.providerID
                        && provider.models.contains(where: { $0.id == mapping.modelID })
                })
            else {
                return nil
            }
            return route.id
        }
    }

    public func normalized(
        providers: [Provider],
        mappings: [String: ModelMapping]
    ) -> ClaudeCodeConfiguration {
        let available = mappedRouteIDs(providers: providers, mappings: mappings)
        var result = self
        if let defaultModel, available.contains(defaultModel) {
            result.defaultModel = defaultModel
        } else {
            let routesByID = Dictionary(
                uniqueKeysWithValues: ClaudeRoute.all.map { ($0.id, $0) }
            )
            result.defaultModel =
                available.first { routeID in
                    routesByID[routeID]?.family == "sonnet"
                        && routesByID[routeID]?.isFamilyDefault == true
                } ?? available.first
        }
        result.contextMode =
            result.defaultModelSupports1MContext(
                providers: providers,
                mappings: mappings
            ) ? .extended1M : .standard
        return result
    }

    public func defaultModelSupports1MContext(
        providers: [Provider],
        mappings: [String: ModelMapping]
    ) -> Bool {
        guard let defaultModel,
            let mapping = mappings[defaultModel],
            let provider = providers.first(where: { $0.id == mapping.providerID }),
            let model = provider.models.first(where: { $0.id == mapping.modelID })
        else {
            return false
        }
        return model.supports1MContext
    }
}
