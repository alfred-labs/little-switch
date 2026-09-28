import Foundation
import LittleSwitchCommon

enum LegacyProviderConfiguration {
    struct Credentials {
        let authMode: AuthMode
        let source: CredentialSource
        let scriptPath: String?
        let refreshInterval: TimeInterval?
    }

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
        case imageInputObservations
        case integration
    }

    static func decode(
        from decoder: Decoder,
        configurationVersion: Int,
        credentials: Credentials? = nil
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
        let credentials = try credentials ?? decodeCredentials(from: values)
        return try Provider(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            baseURL: baseURL,
            authMode: credentials.authMode,
            credentialSource: credentials.source,
            credentialScriptPath: credentials.scriptPath,
            credentialRefreshInterval: credentials.refreshInterval,
            models: values.decode([DiscoveredModel].self, forKey: .models),
            lastRefresh: values.decodeIfPresent(Date.self, forKey: .lastRefresh),
            status: values.decode(ProviderStatus.self, forKey: .status),
            lastError: values.decodeIfPresent(String.self, forKey: .lastError),
            maximumParallelRequests: maximumParallelRequests,
            imageInputOverride: values.decodeIfPresent(
                ProviderImageInputOverride.self, forKey: .imageInputOverride),
            disabledThinkingOverride: values.decodeIfPresent(
                ProviderDisabledThinkingOverride.self, forKey: .disabledThinkingOverride) ?? .default,
            responsesWireOverride: values.decodeIfPresent(
                ProviderResponsesWireOverride.self, forKey: .responsesWireOverride),
            anthropicBaseURL: values.decodeIfPresent(String.self, forKey: .anthropicBaseURL),
            wireProbe: values.decodeIfPresent(ProviderWireProbe.self, forKey: .wireProbe),
            imageInputObservations: ModelImageInputObservationDecoding.decode(
                from: values, forKey: .imageInputObservations),
            integration: values.decodeIfPresent(ProviderIntegration.self, forKey: .integration) ?? .openAICompatible
        )
    }

    private static func decodeCredentials(
        from values: KeyedDecodingContainer<CodingKeys>
    ) throws -> Credentials {
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
        return try Credentials(
            authMode: authMode,
            source: credentialSource,
            scriptPath: values.decodeIfPresent(
                String.self,
                forKey: .credentialScriptPath
            ),
            refreshInterval: values.decodeIfPresent(
                TimeInterval.self,
                forKey: .credentialRefreshInterval
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
