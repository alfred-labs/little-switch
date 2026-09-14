public struct RoutedTarget: Equatable, Sendable {
    public var route: ClaudeRoute
    public var provider: Provider
    public var modelID: String

    public var reference: String {
        provider.reference(to: modelID)
    }

    /// The mapped model's 1M eligibility exactly as the gateway enforces it —
    /// the one capability the catalog must not overstate.
    public var supports1MContext: Bool {
        provider.models.first { $0.id == modelID }?.supports1MContext ?? false
    }
    package init(
        route: ClaudeRoute,
        provider: Provider,
        modelID: String
    ) {
        self.route = route
        self.provider = provider
        self.modelID = modelID
    }

}
