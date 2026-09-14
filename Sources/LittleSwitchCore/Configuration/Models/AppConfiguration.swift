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
    public var openCode: OpenCodeConfiguration
    public var webSearch: WebSearchConfiguration
    public var monitoring: MonitoringConfiguration
    public var relaunchTargets: RelaunchTargets
    public var modelIndicator: ModelIndicator

    public init(
        version: Int = 8,
        providers: [Provider] = [],
        mappings: [String: ModelMapping] = [:],
        autoMode: Bool = true,
        connected: Bool = false,
        claudeCode: ClaudeCodeConfiguration = .disconnected,
        codex: CodexConfiguration = .disconnected,
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
        case openCode
        case webSearch
        case monitoring
        case relaunchTargets
        case modelIndicator
    }

    private struct StoredProvider {
        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case baseURL
            case authMode
            case credentialSource
            case credentialScriptPath
            case credentialRefreshInterval
            case models
            case lastRefresh
            case status
            case lastError
            case maximumParallelRequests
            case imageInputOverride
            case disabledThinkingOverride
            case responsesWireOverride
            case anthropicBaseURL
            case wireProbe
        }

        static func decode(
            from decoder: Decoder,
            configurationVersion: Int
        ) throws -> Provider {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let baseURL = try values.decode(String.self, forKey: .baseURL)
            let maximumParallelRequests: Int
            if values.contains(.maximumParallelRequests) {
                maximumParallelRequests = try values.decode(
                    Int.self,
                    forKey: .maximumParallelRequests
                )
            } else if (1...6).contains(configurationVersion) {
                maximumParallelRequests = legacyMaximumParallelRequests(for: baseURL)
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.maximumParallelRequests,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "maximumParallelRequests is required"
                    )
                )
            }
            guard Provider.maximumParallelRequestsRange.contains(maximumParallelRequests) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .maximumParallelRequests,
                    in: values,
                    debugDescription: "maximumParallelRequests must be between 1 and 32"
                )
            }
            // Pre-header-source-split configurations stored the script
            // source as the auth mode itself: it meant "run a script, send
            // the token as a Bearer header".
            let storedAuthMode = try values.decode(String.self, forKey: .authMode)
            let legacyScriptSource = storedAuthMode == "script"
            let authMode: AuthMode
            if legacyScriptSource || storedAuthMode == "optional-bearer" {
                authMode = .bearer
            } else {
                guard let decodedMode = AuthMode(rawValue: storedAuthMode) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .authMode,
                        in: values,
                        debugDescription: "Unknown authentication mode \(storedAuthMode)"
                    )
                }
                authMode = decodedMode
            }
            let credentialSource: CredentialSource
            if let storedSource = try values.decodeIfPresent(
                CredentialSource.self,
                forKey: .credentialSource
            ) {
                credentialSource = storedSource
            } else {
                credentialSource = legacyScriptSource ? .script : .manual
            }
            return try Provider(
                id: values.decode(UUID.self, forKey: .id),
                name: values.decode(String.self, forKey: .name),
                baseURL: baseURL,
                authMode: authMode,
                credentialSource: credentialSource,
                credentialScriptPath: values.decodeIfPresent(
                    String.self,
                    forKey: .credentialScriptPath
                ),
                credentialRefreshInterval: values.decodeIfPresent(
                    TimeInterval.self,
                    forKey: .credentialRefreshInterval
                ),
                models: values.decode([DiscoveredModel].self, forKey: .models),
                lastRefresh: values.decodeIfPresent(Date.self, forKey: .lastRefresh),
                status: values.decode(ProviderStatus.self, forKey: .status),
                lastError: values.decodeIfPresent(String.self, forKey: .lastError),
                maximumParallelRequests: maximumParallelRequests,
                imageInputOverride: values.decodeIfPresent(
                    ProviderImageInputOverride.self,
                    forKey: .imageInputOverride
                ),
                disabledThinkingOverride: values.decodeIfPresent(
                    ProviderDisabledThinkingOverride.self,
                    forKey: .disabledThinkingOverride
                ) ?? .default,
                responsesWireOverride: values.decodeIfPresent(
                    ProviderResponsesWireOverride.self,
                    forKey: .responsesWireOverride
                ),
                anthropicBaseURL: values.decodeIfPresent(
                    String.self,
                    forKey: .anthropicBaseURL
                ),
                wireProbe: values.decodeIfPresent(
                    ProviderWireProbe.self,
                    forKey: .wireProbe
                )
            )
        }

        private static func legacyMaximumParallelRequests(for baseURL: String) -> Int {
            guard
                let normalizedURL = try? ProviderEndpoint.normalize(baseURL),
                let host = URLComponents(string: normalizedURL)?.host?.lowercased(),
                host == "api.z.ai"
            else {
                return Provider.defaultMaximumParallelRequests
            }
            return ProviderPreset.zai.maximumParallelRequests
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        version = (1...7).contains(storedVersion) ? 8 : storedVersion
        var storedProviders = try values.nestedUnkeyedContainer(forKey: .providers)
        var decodedProviders: [Provider] = []
        while !storedProviders.isAtEnd {
            decodedProviders.append(
                try StoredProvider.decode(
                    from: storedProviders.superDecoder(),
                    configurationVersion: storedVersion
                )
            )
        }
        providers = decodedProviders
        let routeIDs = Set(ClaudeRoute.all.map(\.id))
        mappings =
            try values
            .decode([String: ModelMapping].self, forKey: .mappings)
            .filter { routeIDs.contains($0.key) }
        autoMode = try values.decode(Bool.self, forKey: .autoMode)
        connected = try values.decode(Bool.self, forKey: .connected)
        claudeCode =
            try values.decodeIfPresent(
                ClaudeCodeConfiguration.self,
                forKey: .claudeCode
            ) ?? .disconnected
        codex = try values.decodeIfPresent(CodexConfiguration.self, forKey: .codex) ?? .disconnected
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
