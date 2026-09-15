import Foundation

public struct ModelImageInputKey: Codable, Hashable, Sendable {
    public let providerID: UUID
    public let modelID: String
    public let wire: ModelImageInputWire
    public let endpoint: String

    public init(providerID: UUID, modelID: String, wire: ModelImageInputWire, endpoint: String) {
        self.providerID = providerID
        self.modelID = modelID
        self.wire = wire
        self.endpoint = endpoint
    }
}

public enum ModelImageInputVerdict: String, Codable, Equatable, Sendable {
    case verified
    case unsupported
}

public enum ModelImageInputEvidenceSource: String, Codable, Equatable, Sendable {
    case visualProbe
    case providerRejection
}

/// Only conclusive evidence is durable. A timeout cannot erase a known fact.
public struct ModelImageInputObservation: Codable, Equatable, Sendable {
    public let key: ModelImageInputKey
    public let verdict: ModelImageInputVerdict
    public let source: ModelImageInputEvidenceSource
    public let observedAt: Date

    public init(
        key: ModelImageInputKey,
        verdict: ModelImageInputVerdict,
        source: ModelImageInputEvidenceSource,
        observedAt: Date
    ) {
        self.key = key
        self.verdict = verdict
        self.source = source
        self.observedAt = observedAt
    }
}
