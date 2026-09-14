import Foundation
import LittleSwitchCommon
import LittleSwitchCore

public enum ProviderMutationIntent: Equatable, Sendable {
    case add
    case edit
    case duplicate(sourceID: UUID)
}

public struct ProviderInput: Sendable {
    public var id: UUID?
    public var intent: ProviderMutationIntent
    public var name: String
    public var baseURL: String
    public var authMode: AuthMode
    public var credential: String?
    /// Where the credential comes from: a pasted token or the chosen script.
    public var credentialSource: CredentialSource
    /// Path of the credential script for script authentication; blank keeps
    /// the one already configured, mirroring the credential field.
    public var scriptPath: String?
    public var credentialRefreshInterval: TimeInterval?
    public var contextOverrides: [String: Int]?
    public var maximumParallelRequests: Int
    public var imageInputOverride: ProviderImageInputOverride?
    public var disabledThinkingOverride: ProviderDisabledThinkingOverride
    public var responsesWireOverride: ProviderResponsesWireOverride?
    /// The provider's optional Anthropic surface (split-surface providers
    /// like z.ai); nil means the base URL serves every wire.
    public var anthropicBaseURL: String?

    public init(
        id: UUID? = nil,
        intent: ProviderMutationIntent? = nil,
        name: String,
        baseURL: String,
        authMode: AuthMode,
        credential: String? = nil,
        credentialSource: CredentialSource = .manual,
        scriptPath: String? = nil,
        credentialRefreshInterval: TimeInterval? = nil,
        contextOverrides: [String: Int]? = nil,
        maximumParallelRequests: Int = Provider.defaultMaximumParallelRequests,
        imageInputOverride: ProviderImageInputOverride? = nil,
        disabledThinkingOverride: ProviderDisabledThinkingOverride = .default,
        responsesWireOverride: ProviderResponsesWireOverride? = nil,
        anthropicBaseURL: String? = nil
    ) {
        self.id = id
        self.intent = intent ?? (id == nil ? .add : .edit)
        self.name = name
        self.baseURL = baseURL
        self.authMode = authMode
        self.credential = credential
        self.credentialSource = credentialSource
        self.scriptPath = scriptPath
        self.credentialRefreshInterval = credentialRefreshInterval
        self.contextOverrides = contextOverrides
        self.maximumParallelRequests = maximumParallelRequests
        self.imageInputOverride = imageInputOverride
        self.disabledThinkingOverride = disabledThinkingOverride
        self.responsesWireOverride = responsesWireOverride
        self.anthropicBaseURL = anthropicBaseURL
    }
}
