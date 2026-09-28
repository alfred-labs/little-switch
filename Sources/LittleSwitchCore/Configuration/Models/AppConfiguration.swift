import Foundation
import LittleSwitchCommon

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var providers: [Provider]
    public var mappings: [String: ModelMapping]
    public var autoMode: Bool
    public var connected: Bool
    public var claudeCode: ClaudeCodeConfiguration
    public var codex: CodexConfiguration
    public var chatgpt: ChatGPTConfiguration
    public var openCode: OpenCodeConfiguration
    public var webSearch: WebSearchConfiguration
    public var monitoring: MonitoringConfiguration
    public var relaunchTargets: RelaunchTargets
    public var modelIndicator: ModelIndicator

    public init(
        version: Int = 11,
        providers: [Provider] = [],
        mappings: [String: ModelMapping] = [:],
        autoMode: Bool = true,
        connected: Bool = false,
        claudeCode: ClaudeCodeConfiguration = .disconnected,
        codex: CodexConfiguration = .disconnected,
        chatgpt: ChatGPTConfiguration = .disconnected,
        openCode: OpenCodeConfiguration = .disconnected,
        webSearch: WebSearchConfiguration = .disabled,
        monitoring: MonitoringConfiguration = .init(),
        relaunchTargets: RelaunchTargets = .none,
        modelIndicator: ModelIndicator = .mapsTo
    ) {
        self.version = version
        self.providers = providers
        self.mappings = mappings
        self.autoMode = autoMode
        self.connected = connected
        self.claudeCode = claudeCode
        self.codex = codex
        self.chatgpt = chatgpt
        self.openCode = openCode
        self.webSearch = webSearch
        self.monitoring = monitoring
        self.relaunchTargets = relaunchTargets
        self.modelIndicator = modelIndicator
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case providers
        case mappings
        case autoMode
        case connected
        case claudeCode
        case codex
        case chatgpt
        case openCode
        case webSearch
        case monitoring
        case relaunchTargets
        case modelIndicator
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        version = (1...10).contains(storedVersion) ? 11 : storedVersion
        var storedProviders = try values.nestedUnkeyedContainer(forKey: .providers)
        var decodedProviders: [Provider] = []
        while !storedProviders.isAtEnd {
            let providerDecoder = try storedProviders.superDecoder()
            let provider: Provider
            if storedVersion == 10 {
                provider = try ExperimentalProviderConfiguration.decode(from: providerDecoder)
            } else if storedVersion >= 11 {
                provider = try Provider(from: providerDecoder)
            } else {
                provider = try LegacyProviderConfiguration.decode(
                    from: providerDecoder, configurationVersion: storedVersion)
            }
            decodedProviders.append(provider)
        }
        try StoredProviderValidation.validate(decodedProviders)
        providers = decodedProviders
        let routeIDs = Set(ClaudeRoute.all.map(\.id))
        let storedMappings = try values.decode([String: ModelMapping].self, forKey: .mappings)
        mappings = ClaudeRouteCompatibility.migrate(storedMappings).filter { routeIDs.contains($0.key) }
        autoMode = try values.decode(Bool.self, forKey: .autoMode)
        connected = try values.decode(Bool.self, forKey: .connected)
        claudeCode =
            try values.decodeIfPresent(
                ClaudeCodeConfiguration.self,
                forKey: .claudeCode
            ) ?? .disconnected
        claudeCode.defaultModel = claudeCode.defaultModel.map(ClaudeRouteCompatibility.canonicalID)
        codex = try values.decodeIfPresent(CodexConfiguration.self, forKey: .codex) ?? .disconnected
        chatgpt = try values.decodeIfPresent(ChatGPTConfiguration.self, forKey: .chatgpt) ?? .disconnected
        openCode =
            try values.decodeIfPresent(
                OpenCodeConfiguration.self,
                forKey: .openCode
            ) ?? .disconnected
        webSearch =
            try values.decodeIfPresent(
                WebSearchConfiguration.self,
                forKey: .webSearch
            ) ?? .disabled
        monitoring =
            try values.decodeIfPresent(
                MonitoringConfiguration.self,
                forKey: .monitoring
            ) ?? .init()
        relaunchTargets =
            try values.decodeIfPresent(
                RelaunchTargets.self,
                forKey: .relaunchTargets
            ) ?? .none
        // A hand-edited or forward-written raw value must not brick the whole
        // configuration decode; unknown indicators fall back to the default.
        modelIndicator =
            try values
            .decodeIfPresent(String.self, forKey: .modelIndicator)
            .flatMap(ModelIndicator.init(rawValue:))
            ?? .mapsTo
    }
}
