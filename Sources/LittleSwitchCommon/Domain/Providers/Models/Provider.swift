import Foundation

public struct Provider: Codable, Equatable, Identifiable, Sendable {
    public static let maximumParallelRequestsRange = 1...32
    public static let defaultMaximumParallelRequests = 4

    /// Refresh periods offered for script credentials.
    public static let credentialRefreshIntervalChoices: [TimeInterval] = [
        300, 900, 1_800, 3_600, 21_600, 86_400,
    ]
    public static let defaultCredentialRefreshInterval: TimeInterval = 3_600

    public var id: UUID
    public var name: String
    public var baseURL: String
    public var authMode: AuthMode
    /// Where the credential value comes from: pasted into the editor or
    /// produced by the chosen script. Script sources require a header mode.
    public var credentialSource: CredentialSource
    /// Path of the credential script, chosen by the user in the file system:
    /// it is code that fetches a token, not a secret — only the token it
    /// prints goes to the keychain.
    public var credentialScriptPath: String?
    /// How often the credential script runs while the provider uses script
    /// authentication; nil means the default period.
    public var credentialRefreshInterval: TimeInterval?
    public var models: [DiscoveredModel]
    public var lastRefresh: Date?
    public var status: ProviderStatus
    public var lastError: String?
    public var maximumParallelRequests: Int
    public var imageInputOverride: ProviderImageInputOverride?
    /// Behavior for requests that disable thinking. Defaults to low
    /// effort; `passthrough` preserves the caller's parameters.
    public var disabledThinkingOverride: ProviderDisabledThinkingOverride
    /// Forced Responses wire; nil = automatic detection. See
    /// `ProviderResponsesWireOverride`.
    public var responsesWireOverride: ProviderResponsesWireOverride?
    /// The provider's optional Anthropic surface; when set, the base URL is
    /// the OpenAI-compatible root and messages ride the Anthropic URL.
    public var anthropicBaseURL: String?
    /// Last endpoint-route probe, refreshed on every save. See
    /// `ProviderWireProbe`.
    public var wireProbe: ProviderWireProbe?
    /// Conclusive image evidence, separate from advertised model metadata.
    public var imageInputObservations: [ModelImageInputObservation]

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        authMode: AuthMode,
        credentialSource: CredentialSource = .manual,
        credentialScriptPath: String? = nil,
        credentialRefreshInterval: TimeInterval? = nil,
        models: [DiscoveredModel] = [],
        lastRefresh: Date? = nil,
        status: ProviderStatus = .idle,
        lastError: String? = nil,
        maximumParallelRequests: Int = Provider.defaultMaximumParallelRequests,
        imageInputOverride: ProviderImageInputOverride? = nil,
        disabledThinkingOverride: ProviderDisabledThinkingOverride = .default,
        responsesWireOverride: ProviderResponsesWireOverride? = nil,
        anthropicBaseURL: String? = nil,
        wireProbe: ProviderWireProbe? = nil,
        imageInputObservations: [ModelImageInputObservation] = []
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.authMode = authMode
        self.credentialSource = credentialSource
        self.credentialScriptPath = credentialScriptPath
        self.credentialRefreshInterval = credentialRefreshInterval
        self.models = models
        self.lastRefresh = lastRefresh
        self.status = status
        self.lastError = lastError
        self.maximumParallelRequests = maximumParallelRequests
        self.imageInputOverride = imageInputOverride
        self.disabledThinkingOverride = disabledThinkingOverride
        self.responsesWireOverride = responsesWireOverride
        self.anthropicBaseURL = anthropicBaseURL
        self.wireProbe = wireProbe
        self.imageInputObservations = imageInputObservations
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, authMode, credentialSource, credentialScriptPath
        case credentialRefreshInterval, models, lastRefresh, status, lastError
        case maximumParallelRequests, imageInputOverride, disabledThinkingOverride
        case responsesWireOverride, anthropicBaseURL, wireProbe, imageInputObservations
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            baseURL: try values.decode(String.self, forKey: .baseURL),
            authMode: try values.decode(AuthMode.self, forKey: .authMode),
            credentialSource: try values.decode(CredentialSource.self, forKey: .credentialSource),
            credentialScriptPath: try values.decodeIfPresent(String.self, forKey: .credentialScriptPath),
            credentialRefreshInterval: try values.decodeIfPresent(
                TimeInterval.self, forKey: .credentialRefreshInterval),
            models: try values.decode([DiscoveredModel].self, forKey: .models),
            lastRefresh: try values.decodeIfPresent(Date.self, forKey: .lastRefresh),
            status: try values.decode(ProviderStatus.self, forKey: .status),
            lastError: try values.decodeIfPresent(String.self, forKey: .lastError),
            maximumParallelRequests: try values.decode(Int.self, forKey: .maximumParallelRequests),
            imageInputOverride: try values.decodeIfPresent(
                ProviderImageInputOverride.self, forKey: .imageInputOverride),
            disabledThinkingOverride: try values.decode(
                ProviderDisabledThinkingOverride.self, forKey: .disabledThinkingOverride),
            responsesWireOverride: try values.decodeIfPresent(
                ProviderResponsesWireOverride.self, forKey: .responsesWireOverride),
            anthropicBaseURL: try values.decodeIfPresent(String.self, forKey: .anthropicBaseURL),
            wireProbe: try values.decodeIfPresent(ProviderWireProbe.self, forKey: .wireProbe),
            imageInputObservations: ModelImageInputObservationDecoding.decode(
                from: values, forKey: .imageInputObservations)
        )
    }

    public func imageInputsAccepted(for model: DiscoveredModel) -> Bool {
        switch imageInputOverride {
        case .enabled:
            return true
        case .disabled:
            return false
        case nil:
            return model.supportsImageInput ?? true
        }
    }

    public func reference(to modelID: String) -> String {
        "\(name)/\(modelID)"
    }
}
