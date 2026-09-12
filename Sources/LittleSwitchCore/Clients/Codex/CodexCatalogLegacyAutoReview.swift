import Foundation

extension CodexCatalog {
    /// Reconstructs the former managed catalog for update detection and rollback.
    /// Only the reserved route and its explicit overrides change; arbitrary
    /// instructions and provider/model names are never rewritten.
    package static func legacyAutoReviewData(_ data: Data) throws -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var models = root["models"] as? [[String: Any]]
        else {
            throw Error.empty
        }
        guard models.contains(where: { $0["slug"] as? String == managedAutoReviewModel }) else {
            return data
        }
        // The old managed alias won collisions with Codex's native reviewer.
        models.removeAll { $0["slug"] as? String == legacyManagedAutoReviewModel }
        for index in models.indices {
            if models[index]["auto_review_model_override"] as? String == managedAutoReviewModel {
                models[index]["auto_review_model_override"] = legacyManagedAutoReviewModel
            }
            if models[index]["slug"] as? String == managedAutoReviewModel {
                models[index]["slug"] = legacyManagedAutoReviewModel
                models[index]["display_name"] = legacyManagedAutoReviewModel
            }
            models[index]["priority"] = index
        }
        root["models"] = models
        var encoded = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        encoded.append(UInt8(ascii: "\n"))
        return encoded
    }
}
