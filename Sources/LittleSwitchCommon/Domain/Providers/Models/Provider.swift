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
        wireProbe: ProviderWireProbe? = nil
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
