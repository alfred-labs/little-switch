import Foundation

package enum ChatGPTCatalog {
    private typealias Field = ChatGPTNativeContract.CatalogField

    package enum MergeError: Error, Equatable {
        case invalidNativeCatalog
        case invalidManagedModel
        case duplicateModelSlug
        case identifierCollision
    }

    package static func merge(nativeData: Data, models: [ChatGPTCatalogModel]) throws -> Data {
        guard let firstModel = models.first else { return nativeData }
        guard var root = try? JSONSerialization.jsonObject(with: nativeData) as? [String: Any],
            let nativeModels = root[Field.models.rawValue] as? [[String: Any]]
        else { throw MergeError.invalidNativeCatalog }
        let versions = try nativeArray(root[Field.versions.rawValue])
        let categories = try nativeArray(root[Field.categories.rawValue])
        try validate(models, nativeModels: nativeModels)

        root[Field.models.rawValue] = nativeModels + models.map(modelRecord)
        if !versions.isEmpty {
            try rejectIdentifierCollision(
                "little-switch", in: versions, key: Field.id.rawValue)
            root[Field.versions.rawValue] = versions + [versionRecord(models, title: firstModel.title)]
        }
        // Preset-free versions resolve their selectable options through the
        // matching category. A slug alone does not survive native selection validation.
        if !versions.isEmpty || !categories.isEmpty {
            for model in models {
                try rejectIdentifierCollision(
                    "little-switch:\(model.slug)", in: categories, key: Field.category.rawValue)
            }
            root[Field.categories.rawValue] = categories + models.map(categoryRecord)
        }
        return try JSONSerialization.data(withJSONObject: root)
    }

    private static func nativeArray(_ value: Any?) throws -> [Any] {
        guard let value else { return [] }
        guard let array = value as? [Any] else { throw MergeError.invalidNativeCatalog }
        return array
    }

    private static func validate(_ models: [ChatGPTCatalogModel], nativeModels: [[String: Any]]) throws {
        var slugs = Set<String>()
        for model in nativeModels {
            guard let slug = model[Field.slug.rawValue] as? String, !slug.isEmpty else {
                throw MergeError.invalidNativeCatalog
            }
            slugs.insert(collisionKey(slug))
        }
        for model in models {
            for value in [model.slug, model.title] {
                guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw MergeError.invalidManagedModel
                }
            }
            guard slugs.insert(collisionKey(model.slug)).inserted else { throw MergeError.duplicateModelSlug }
        }
    }

    private static func collisionKey(_ value: String) -> String {
        value.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func rejectIdentifierCollision(_ identifier: String, in rows: [Any], key: String) throws {
        let identifierKey = collisionKey(identifier)
        for row in rows {
            guard let row = row as? [String: Any], let value = row[key] as? String else { continue }
            if collisionKey(value) == identifierKey {
                throw MergeError.identifierCollision
            }
        }
    }

    private static func modelRecord(_ model: ChatGPTCatalogModel) -> [String: Any] {
        [
            Field.slug.rawValue: model.slug,
            Field.title.rawValue: model.title,
            Field.description.rawValue: "LittleSwitch",
            Field.enabledTools.rawValue: [String](),
            Field.configurableThinkingEffort.rawValue: false,
            Field.reasoningType.rawValue: ChatGPTNativeContract.ReasoningType.none
                .rawValue,
        ]
    }

    private static func versionRecord(_ models: [ChatGPTCatalogModel], title: String) -> [String: Any] {
        [
            Field.id.rawValue: "little-switch",
            Field.displayText.rawValue: title,
            Field.slugs.rawValue: models.map(\.slug),
        ]
    }

    private static func categoryRecord(_ model: ChatGPTCatalogModel) -> [String: Any] {
        [
            Field.category.rawValue: "little-switch:\(model.slug)",
            Field.defaultModel.rawValue: model.slug,
            Field.humanCategoryName.rawValue: model.title,
            Field.humanCategoryShortName.rawValue: model.title,
            Field.shortExplainer.rawValue: NSNull(),
            Field.supportedModels.rawValue: [model.slug],
            Field.tagline.rawValue: NSNull(),
            Field.title.rawValue: model.title,
        ]
    }
}
