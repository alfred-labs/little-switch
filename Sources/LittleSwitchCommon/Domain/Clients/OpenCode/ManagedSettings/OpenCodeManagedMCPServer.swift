public struct OpenCodeManagedMCPServer: Codable, Equatable, Sendable {
    /// The journal owns this MCP dictionary key, independently of the model provider ID.
    public var name: String
    public var type: String
    public var url: String
    public var enabled: Bool
    public var oauth: Bool
    public var timeout: Int

    public init(
        name: String = "little-switch",
        type: String,
        url: String,
        enabled: Bool,
        oauth: Bool,
        timeout: Int
    ) {
        self.name = name
        self.type = type
        self.url = url
        self.enabled = enabled
        self.oauth = oauth
        self.timeout = timeout
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, url, enabled, oauth, timeout
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            // Journals predating explicit names managed only mcp.little-switch.
            name: try values.decodeIfPresent(String.self, forKey: .name) ?? "little-switch",
            type: try values.decode(String.self, forKey: .type),
            url: try values.decode(String.self, forKey: .url),
            enabled: try values.decode(Bool.self, forKey: .enabled),
            oauth: try values.decode(Bool.self, forKey: .oauth),
            timeout: try values.decode(Int.self, forKey: .timeout)
        )
    }

    public static let littleSwitch = Self(
        name: "web",
        type: "remote",
        url: "https://127.0.0.1:11436/api/mcp",
        enabled: true,
        oauth: false,
        timeout: 150_000
    )
}
