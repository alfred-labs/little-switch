/// Suffix appended to route names in the client-facing catalog. A user
/// appearance preference — it never affects routing or resolution.
public enum ModelIndicator: String, Codable, CaseIterable, Sendable {
    case none
    case swap
    case equilibrium
    case routed
    case mapsTo

    public var symbol: String? {
        switch self {
        case .none: nil
        case .swap: "⇄"
        case .equilibrium: "⇌"
        case .routed: "⇢"
        case .mapsTo: "↦"
        }
    }
}
