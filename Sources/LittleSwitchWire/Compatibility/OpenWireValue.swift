/// Keeps future protocol values without widening the official enum's cases.
public enum OpenWireValue<Known>: Sendable, WireCodable
where Known: RawRepresentable & Sendable, Known.RawValue == String {
    case known(Known)
    case unknown(String)

    public init(rawValue: String) {
        if let known = Known(rawValue: rawValue) {
            self = .known(known)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .known(let value): value.rawValue
        case .unknown(let value): value
        }
    }

    public init(wireJSON: JSONValue) throws {
        self.init(rawValue: try String(wireJSON: wireJSON))
    }

    public func wireJSON() -> JSONValue { .string(rawValue) }
}

extension OpenWireValue: Equatable where Known: Equatable {}
extension OpenWireValue: Hashable where Known: Hashable {}
