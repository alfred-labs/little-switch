import Foundation

/// A decoded value and the original bytes for protocol-transparent passthrough.
public struct WireDocument<Value: WireCodable>: Sendable {
    public let originalData: Data
    public let value: Value
}

public enum WireCodec {
    public static func decode<Value: WireCodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> WireDocument<Value> {
        guard String(data: data, encoding: .utf8) != nil else {
            throw WireCodingError(.invalidJSON)
        }
        let json: JSONValue
        do {
            json = try JSONValue.parse(data)
        } catch {
            throw WireCodingError(.invalidJSON)
        }
        do {
            return try WireDocument(originalData: data, value: Value(wireJSON: json))
        } catch let error as WireCodingError {
            throw error
        } catch {
            throw WireCodingError(.typeMismatch)
        }
    }

    public static func encode<Value: WireCodable>(_ value: Value) throws -> Data {
        do {
            return try value.wireJSON().serializedData()
        } catch let error as WireCodingError {
            throw error
        } catch {
            throw WireCodingError(.invalidJSON)
        }
    }
}
