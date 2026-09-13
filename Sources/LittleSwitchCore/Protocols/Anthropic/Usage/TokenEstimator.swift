import Foundation
import LittleSwitchWire

public enum TokenEstimator {
    public enum Error: Swift.Error {
        case invalidRoot
    }

    public static func estimate(_ request: Data) throws -> Int {
        guard let root = try WireCodec.decode(JSONValue.self, from: request).value.anthropicObject else {
            throw Error.invalidRoot
        }
        return try estimate(root: root)
    }

    /// Estimates from an already-parsed request root, so callers that parsed
    /// the body for routing do not re-serialize through JSON.
    static func estimate(root: [String: JSONValue]) throws -> Int {
        var byteCount = semanticBytes(root[AnthropicCountTokensProjection.Key.system.rawValue])
        if let messages = root[AnthropicCountTokensProjection.Key.messages.rawValue]?.anthropicObjects {
            for message in messages {
                byteCount += semanticBytes(message[AnthropicMessageParam.Key.role.rawValue])
                byteCount += semanticBytes(message[AnthropicMessageParam.Key.content.rawValue])
            }
        }
        if let tools = root[AnthropicCountTokensProjection.Key.tools.rawValue]?.anthropicObjects {
            for tool in tools {
                byteCount += semanticBytes(tool[AnthropicToolDefinition.Key.name.rawValue])
                byteCount += semanticBytes(tool[AnthropicToolDefinition.Key.description.rawValue])
                byteCount += semanticBytes(tool[AnthropicToolDefinition.Key.inputSchema.rawValue])
            }
        }
        guard byteCount > 0 else {
            return 0
        }
        return max(1, (byteCount + 3) / 4)
    }

    private static func semanticBytes(_ value: JSONValue?) -> Int {
        switch value {
        case .string(let string):
            return string.utf8.count
        case .array(let array):
            return array.reduce(0) { $0 + semanticBytes($1) }
        case .object(let dictionary):
            if dictionary[AnthropicImageParam.Key.type.rawValue]?.string == AnthropicImageParamType.image.rawValue {
                return 0
            }
            return dictionary.reduce(0) { count, element in
                count + element.key.utf8.count + semanticBytes(element.value)
            }
        case .numberLiteral(let number):
            return number.rawValue.utf8.count
        case .boolean:
            return 1
        case .null, .none:
            return 0
        }
    }
}
