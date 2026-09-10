import Foundation

/// Endpoint routes probed at provider save time, so the first Codex or Claude
/// request never pays a discovery 404. Recorded on the provider for display
/// and used to seed the Responses capability ledger.
public struct ProviderWireProbe: Codable, Equatable, Sendable {
    public var messages: ProviderWireAvailability
    public var responses: ProviderWireAvailability
    public var chatCompletions: ProviderWireAvailability
    public var date: Date

    public init(
        messages: ProviderWireAvailability,
        responses: ProviderWireAvailability,
        chatCompletions: ProviderWireAvailability,
        date: Date = Date()
    ) {
        self.messages = messages
        self.responses = responses
        self.chatCompletions = chatCompletions
        self.date = date
    }

    /// The routing evidence a probe proves. Only an absent `/v1/responses`
    /// route is conclusive enough to seed the Responses ledger: lenient
    /// front doors answer 200/400 to every path (z.ai itself returns
    /// `200 {"code":401,...}` on an expired token), and the runtime learner
    /// already records true-positive 2xx from real traffic — so a probe
    /// "available" is display evidence, never routing evidence.
    public var responsesRouteAbsent: Bool {
        responses == .absent
    }
}
