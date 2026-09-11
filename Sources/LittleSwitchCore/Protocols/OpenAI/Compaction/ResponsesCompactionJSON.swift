import Foundation

enum ResponsesCompactionJSON {
    static func object(_ data: Data, error: ResponsesCompactionError) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw error
        }
        return object
    }

    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func text(_ object: Any) throws -> String {
        // JSONSerialization always produces valid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: try data(object), as: UTF8.self)
    }

    static func nonempty(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func kind(_ item: [String: Any], error: ResponsesCompactionError) throws -> String {
        if let kind = nonempty(item["type"]) { return kind }
        guard item["type"] == nil, nonempty(item["role"]) != nil else { throw error }
        return "message"
    }

    static func reference(_ index: Int) -> String {
        String(format: "item_%06d", index + 1)
    }
}
