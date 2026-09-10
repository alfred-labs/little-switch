/// One probe's verdict for a single provider endpoint route.
public enum ProviderWireAvailability: String, Codable, Sendable {
    /// The route answered in a way only an existing route can: 2xx, or a
    /// body-validation rejection (400/422). Verified live: z.ai's FastAPI
    /// answers 422 for `/v1/messages`, a non-FastAPI gateway 400 on all three
    /// routes.
    case available
    /// The route does not exist. 404 is FastAPI's exact
    /// `{"detail":"Not Found"}`; 405 matches the runtime classifier — a
    /// method mismatch on POST still fails every real request, so "route
    /// exists but not for POST" routes like "absent".
    case absent
    /// A firewall, auth wall, quota, or outage spoke instead of the route
    /// (401/402/403/429/5xx, or the request never completed). Says nothing
    /// about the endpoint; routing stays on its previous evidence.
    case unknown

    package init(status: UInt) {
        switch status {
        case 404, 405:
            self = .absent
        case 200...400, 422:
            self = .available
        default:
            self = .unknown
        }
    }
}
