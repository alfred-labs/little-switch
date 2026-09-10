import Foundation

/// Remembers, per provider, whether its `/v1/responses` endpoint answered.
///
/// Replaces a hardcoded base-URL allowlist: the first native attempt is
/// classified by status (2xx means native Responses works, 404/405 mean the
/// route does not exist and the chat-completions adapter must serve the
/// provider), and later requests skip straight to the learned path.
public actor ResponsesCapabilityLedger {
    public init() {}

    private var supportsNativeResponses: [UUID: Bool] = [:]

    public func verdict(for providerID: UUID) -> Bool? {
        supportsNativeResponses[providerID]
    }

    /// Every learned verdict, for presentation and polling.
    public func verdicts() -> [UUID: Bool] {
        supportsNativeResponses
    }

    public func record(providerID: UUID, supportsNative: Bool) {
        supportsNativeResponses[providerID] = supportsNative
    }
}
