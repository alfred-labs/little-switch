import Foundation

public enum TokenEstimator {
    public enum Error: Swift.Error {
        case invalidRoot
    }

    public static func estimate(_ request: Data) throws -> Int {
        guard let root = try JSONSerialization.jsonObject(with: request) as? [String: Any] else {
            throw Error.invalidRoot
        }
        return try estimate(root: root)
    }

    /// Estimates from an already-parsed request root, so callers that parsed
    /// the body for routing do not re-serialize through JSON.
    public static func estimate(root: [String: Any]) throws -> Int {
        var byteCount = semanticBytes(root["system"])
        if let messages = root["messages"] as? [[String: Any]] {
            for message in messages {
                byteCount += semanticBytes(message["role"])
                byteCount += semanticBytes(message["content"])
            }
        }
        if let tools = root["tools"] as? [[String: Any]] {
            for tool in tools {
                byteCount += semanticBytes(tool["name"])
                byteCount += semanticBytes(tool["description"])
                byteCount += semanticBytes(tool["input_schema"])
            }
        }
        guard byteCount > 0 else {
            return 0
        }
        return max(1, (byteCount + 3) / 4)
    }

    private static func semanticBytes(_ value: Any?) -> Int {
        switch value {
        case let string as String:
            return string.utf8.count
        case let array as [Any]:
            return array.reduce(0) { $0 + semanticBytes($1) }
        case let dictionary as [String: Any]:
            if dictionary["type"] as? String == "image" {
                return 0
            }
            return dictionary.reduce(0) { count, element in
                count + element.key.utf8.count + semanticBytes(element.value)
            }
        case let number as NSNumber:
            return number.stringValue.utf8.count
        default:
            return 0
        }
    }
}
