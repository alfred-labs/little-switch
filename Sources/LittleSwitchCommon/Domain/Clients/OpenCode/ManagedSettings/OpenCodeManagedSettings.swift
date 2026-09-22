public struct OpenCodeManagedSettings: Codable, Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case noExposedModel
        case ambiguousModelIdentifiers
    }

    public static let providerID = "little-switch"

    public var model: String
    public var provider: OpenCodeManagedProvider
    /// Presence records MCP ownership; legacy journals decode a missing value as nil.
    public var mcp: OpenCodeManagedMCPServer?

    public init(
        model: String,
        provider: OpenCodeManagedProvider,
        mcp: OpenCodeManagedMCPServer? = nil
    ) {
        self.model = model
        self.provider = provider
        self.mcp = mcp
    }
}
