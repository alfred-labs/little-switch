import Foundation
import LittleSwitchCommon

/// Reconstructs only known managed model identifiers. A complete catalog match
/// remains necessary, including the reviewer's identity and every capability.
struct CodexProfileLegacyIdentifiers {
    let modelSlug: String
    let catalogData: Data

    static func resolve(
        modelSlug: String,
        catalogData: Data,
        providers: [Provider],
        configuration: CodexConfiguration
    ) throws -> Self? {
        var aliases: [String: String] = [:]
        var seenAliases: Set<String> = []
        for target in configuration.exposedModels(in: providers) {
            let canonical = CodexCatalog.slug(for: target)
            let legacy = target.provider.reference(to: target.model.id).lowercased()
            // An ambiguous old alias no longer has a safe gateway route.
            guard aliases.updateValue(legacy, forKey: canonical) == nil,
                seenAliases.insert(legacy).inserted
            else {
                return nil
            }
        }
        guard let legacyModel = aliases[modelSlug],
            var root = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
            var models = root["models"] as? [[String: Any]]
        else {
            return nil
        }
        var rewritten: Set<String> = []
        for index in models.indices {
            guard models[index]["supported_in_api"] as? Bool == true,
                let slug = models[index]["slug"] as? String,
                let alias = aliases[slug]
            else {
                continue
            }
            models[index]["slug"] = alias
            rewritten.insert(slug)
        }
        guard rewritten == Set(aliases.keys) else {
            return nil
        }
        root["models"] = models
        var data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        return Self(modelSlug: legacyModel, catalogData: data)
    }
}
