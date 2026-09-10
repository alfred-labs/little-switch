import Foundation

/// Whether a provider's `/v1/responses` route can serve namespaced tool
/// declarations natively, established by one bounded behavioral probe at
/// save time. Display evidence only: the gateway flattens namespaces into
/// plain functions regardless, so no routing decision reads this verdict.
public enum ProviderNamespaceVerdict: String, Codable, Equatable, Sendable {
    /// The route answered 2xx and emitted a call the probe tool's declared
    /// child explains — the backend serves namespace shapes.
    case restored
    /// The route answered 2xx but never called the probe tool: the backend
    /// accepted the namespace shape and ran nothing (the observed SGLang
    /// behavior) or is a lenient front door that runs nothing.
    case silentlyDropped
    /// A schema-validation rejection: the route cannot accept the namespace
    /// tool shape at all. Auth, quota, and timeout answers are excluded —
    /// they say nothing about the shape, like for the wire probe.
    case rejected
    /// Inconclusive: transport failure, server error, or an unreadable body.
    case unknown
}

/// The last save-time namespace probe of a provider's Responses route. See
/// `ProviderNamespaceProber` for the request shape.
public struct ProviderNamespaceProbe: Codable, Equatable, Sendable {
    public var verdict: ProviderNamespaceVerdict
    /// The model the probe generation ran on; nil when discovery produced
    /// no model to probe with.
    public var model: String?
    public var date: Date

    public init(verdict: ProviderNamespaceVerdict, model: String?, date: Date = Date()) {
        self.verdict = verdict
        self.model = model
        self.date = date
    }
}
