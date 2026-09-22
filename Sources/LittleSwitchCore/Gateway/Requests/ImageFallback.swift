import Foundation
import LittleSwitchWire

public enum ImageFallback {
    public static let notice = "[Image omitted: the selected model does not accept image input.]"

    public struct Replacement: Equatable, Sendable {
        public var body: Data
        public var didReplace: Bool
    }

    public static func shouldRetry(
        status: Int,
        responseBody: Data,
        originalRequest: Data
    ) -> Bool {
        guard status == 400,
            (try? replacingImages(in: originalRequest)) != nil,
            let root = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any],
            root["type"] as? String == "error",
            let error = root["error"] as? [String: Any],
            error["type"] as? String == "invalid_request_error",
            let message = (error["message"] as? String)?.lowercased()
        else {
            return false
        }
        let namesCapability = message.contains("image") || message.contains("vision")
        let rejectsCapability = [
            "unsupported",
            "does not support",
            "doesn't support",
            "not support",
            "cannot process",
            "can't process",
        ].contains { message.contains($0) }
        return namesCapability && rejectsCapability
    }

    public static func replacingImages(in request: Data) throws -> Replacement? {
        let object = try WireCodec.decode(JSONValue.self, from: request).value
        switch object {
        case .object, .array: break
        default: throw WireCodingError(.typeMismatch)
        }
        guard var root = object.object, var messages = root[AnthropicCountTokensProjection.Key.messages.rawValue]?.array
        else {
            return nil
        }
        var didReplace = false
        for index in messages.indices {
            guard var message = messages[index].object else { continue }
            let key = AnthropicMessageParam.Key.content.rawValue
            message[key] = try rewriteContent(message[key], scope: .message, didReplace: &didReplace)
            messages[index] = .object(message)
        }
        guard didReplace else { return nil }
        root[AnthropicCountTokensProjection.Key.messages.rawValue] = .array(messages)
        let data = try WireCodec.encode(JSONValue.object(root))
        return Replacement(body: data, didReplace: true)
    }

    private enum ContentScope { case message, toolResult, document }

    private static func rewriteContent(
        _ value: JSONValue?, scope: ContentScope, didReplace: inout Bool
    ) throws -> JSONValue? {
        guard let blocks = value?.array else { return value }
        return .array(try blocks.map { try rewriteBlock($0, scope: scope, didReplace: &didReplace) })
    }

    /// Only the Anthropic content graph is traversed. Tool input, schemas,
    /// text extensions and unknown blocks remain opaque even if they look like images.
    private static func rewriteBlock(
        _ value: JSONValue, scope: ContentScope, didReplace: inout Bool
    ) throws -> JSONValue {
        guard var block = value.object else { return value }
        let typeKey = AnthropicImageParam.Key.type.rawValue
        let contentKey = AnthropicToolResultParam.Key.content.rawValue
        switch block[typeKey]?.string {
        case AnthropicImageParamType.image.rawValue:
            didReplace = true
            return try AnthropicTextParam(text: notice, type: .text).wireJSON()
        case AnthropicToolResultParamType.toolResult.rawValue where scope == .message:
            block[contentKey] = try rewriteContent(block[contentKey], scope: .toolResult, didReplace: &didReplace)
        case AnthropicDocumentParamType.document.rawValue where scope != .document:
            let key = AnthropicDocumentParam.Key.source.rawValue
            guard var source = block[key]?.object, source[typeKey] == .string("content") else { return value }
            source[contentKey] = try rewriteContent(source[contentKey], scope: .document, didReplace: &didReplace)
            block[key] = .object(source)
        case "web_fetch_tool_result" where scope == .message:
            guard var result = block[contentKey]?.object, result[typeKey] == .string("web_fetch_result"),
                let document = result[contentKey],
                document.object?[typeKey]
                    == .string(AnthropicDocumentParamType.document.rawValue)
            else { return value }
            result[contentKey] = try rewriteBlock(document, scope: .toolResult, didReplace: &didReplace)
            block[contentKey] = .object(result)
        default: return value
        }
        return .object(block)
    }
}
