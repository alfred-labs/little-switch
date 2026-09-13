public enum JSONPresence<Value: Sendable>: Sendable {
    case absent
    case null
    case value(Value)

    /// Explicitly treats both absence and JSON null as unavailable to a consumer.
    public var value: Value? {
        guard case .value(let value) = self else { return nil }
        return value
    }
}

extension JSONPresence: Equatable where Value: Equatable {}
extension JSONPresence: Hashable where Value: Hashable {}
