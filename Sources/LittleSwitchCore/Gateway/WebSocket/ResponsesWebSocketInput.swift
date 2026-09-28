import Foundation
import LittleSwitchWire

/// Only compact, validated arrays enter replay storage. Joining them changes
/// their outer delimiters without decoding existing items or altering bytes.
struct ResponsesWebSocketInput: Sendable {
    let data: Data
    private let itemCount: Int

    init(_ items: [JSONValue]) throws {
        data = try JSONValue.array(items).serializedData()
        itemCount = items.count
    }

    private init(data: Data, itemCount: Int) {
        self.data = data
        self.itemCount = itemCount
    }

    func bytes(appending other: Self) -> Int {
        data.count + other.data.count - 2 + (itemCount > 0 && other.itemCount > 0 ? 1 : 0)
    }

    func appending(_ other: Self) -> Self {
        guard itemCount > 0 else { return other }
        guard other.itemCount > 0 else { return self }
        var joined = Data()
        joined.reserveCapacity(bytes(appending: other))
        joined.append(data.dropLast())
        joined.append(0x2C)
        joined.append(other.data.dropFirst())
        return Self(data: joined, itemCount: itemCount + other.itemCount)
    }
}
