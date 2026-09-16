/// A native Claude family alias and the concrete reference it selects.
/// The catalog and managed environment share this presentation so discovery
/// reuses the native picker entry instead of adding a context variant.
public struct ClaudeCodeModelChoice: Equatable, Sendable, Identifiable {
    public let route: ClaudeRoute
    public let contextMode: ClaudeCodeContextMode
    public let indicator: ModelIndicator

    public init(route: ClaudeRoute, supports1MContext: Bool, indicator: ModelIndicator = .mapsTo) {
        self.route = route
        contextMode = supports1MContext ? .extended1M : .standard
        self.indicator = indicator
    }

    public var id: String { route.family }

    public var reference: String {
        contextMode == .extended1M ? "\(route.id)[1m]" : route.id
    }

    public var label: String {
        let name = baseLabel
        return contextMode == .extended1M ? "\(name) (1M context)" : name
    }

    /// The family label without context presentation; Desktop adds its own
    /// localized 1M suffix after combining this override with discovery.
    public var baseLabel: String {
        indicator.symbol.map { "\(route.modelDisplayName) \($0)" } ?? route.modelDisplayName
    }

    public var description: String { "Via LittleSwitch" }

    public static func available(
        providers: [Provider], mappings: [String: ModelMapping], indicator: ModelIndicator = .mapsTo
    ) -> [ClaudeCodeModelChoice] {
        ClaudeRoute.all.compactMap { route in
            guard let mapping = mappings[route.id],
                let provider = providers.first(where: { $0.id == mapping.providerID }),
                let model = provider.models.first(where: { $0.id == mapping.modelID })
            else {
                return nil
            }
            return ClaudeCodeModelChoice(route: route, supports1MContext: model.supports1MContext, indicator: indicator)
        }
    }
}
