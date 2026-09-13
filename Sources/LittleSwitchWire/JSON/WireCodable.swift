import OrderedJSON

public typealias JSONValue = OrderedJSON.JSONValue
public typealias JSONNumber = OrderedJSON.JSONNumberLiteral

public protocol WireCodable: Sendable {
    init(wireJSON: JSONValue) throws
    func wireJSON() throws -> JSONValue
}

extension JSONValue: WireCodable {
    public init(wireJSON: JSONValue) { self = wireJSON }
    public func wireJSON() -> JSONValue { self }
}

extension String: WireCodable {
    public init(wireJSON: JSONValue) throws {
        guard case .string(let value) = wireJSON else {
            throw WireCodingError(.typeMismatch)
        }
        self = value
    }

    public func wireJSON() -> JSONValue { .string(self) }
}

extension Bool: WireCodable {
    public init(wireJSON: JSONValue) throws {
        guard case .boolean(let value) = wireJSON else {
            throw WireCodingError(.typeMismatch)
        }
        self = value
    }

    public func wireJSON() -> JSONValue { .boolean(self) }
}

extension Int: WireCodable {
    public init(wireJSON: JSONValue) throws {
        guard case .numberLiteral(let value) = wireJSON else {
            throw WireCodingError(.typeMismatch)
        }
        do {
            self = try value.integerValue()
        } catch {
            throw WireCodingError(.unrepresentableNumber)
        }
    }

    public func wireJSON() -> JSONValue { .integer(self) }
}

extension JSONNumber: WireCodable {
    public init(wireJSON: JSONValue) throws {
        guard case .numberLiteral(let value) = wireJSON else {
            throw WireCodingError(.typeMismatch)
        }
        self = value
    }

    public func wireJSON() -> JSONValue { .numberLiteral(self) }
}

extension Array: WireCodable where Element: WireCodable {
    public init(wireJSON: JSONValue) throws {
        guard case .array(let values) = wireJSON else {
            throw WireCodingError(.typeMismatch)
        }
        self = try values.enumerated().map { index, value in
            do {
                return try Element(wireJSON: value)
            } catch let error as WireCodingError {
                throw error.prepending(String(index))
            }
        }
    }

    public func wireJSON() throws -> JSONValue {
        .array(try map { try $0.wireJSON() })
    }
}

extension Optional: WireCodable where Wrapped: WireCodable {
    public init(wireJSON: JSONValue) throws {
        self = wireJSON.isNull ? nil : try Wrapped(wireJSON: wireJSON)
    }

    public func wireJSON() throws -> JSONValue {
        try self?.wireJSON() ?? .null
    }
}
