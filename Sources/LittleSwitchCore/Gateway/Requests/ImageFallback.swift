import Foundation

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
        let object = try JSONSerialization.jsonObject(with: request)
        let replacement = rewrite(object)
        guard replacement.didReplace else {
            return nil
        }
        let data = try JSONSerialization.data(
            withJSONObject: replacement.value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return Replacement(body: data, didReplace: true)
    }

    private static func rewrite(_ value: Any) -> (value: Any, didReplace: Bool) {
        if let dictionary = value as? [String: Any] {
            if dictionary["type"] as? String == "image" {
                return (["type": "text", "text": notice], true)
            }
            var result: [String: Any] = [:]
            var replaced = false
            for (key, child) in dictionary {
                let rewritten = rewrite(child)
                result[key] = rewritten.value
                replaced = replaced || rewritten.didReplace
            }
            return (result, replaced)
        }
        if let array = value as? [Any] {
            var result: [Any] = []
            var replaced = false
            result.reserveCapacity(array.count)
            for child in array {
                let rewritten = rewrite(child)
                result.append(rewritten.value)
                replaced = replaced || rewritten.didReplace
            }
            return (result, replaced)
        }
        return (value, false)
    }
}
