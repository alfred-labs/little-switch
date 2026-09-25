import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTCatalogSelectionTests {
    @Test(arguments: [false, true])
    func presetFreeVersionHasASelectableCategory(existingCategories: Bool) throws {
        var native: [String: Any] = [
            "models": [["slug": "native", "title": "Native"]],
            "versions": [["id": "native", "slugs": ["native"]]],
        ]
        if existingCategories {
            native["categories"] = [["category": "native", "default_model": "native", "unknown": true]]
        }
        let result = try ChatGPTCatalog.merge(
            nativeData: JSONSerialization.data(withJSONObject: native),
            models: [.init(slug: "local:small", title: "Local/Small")])
        let root = try chatJSONObject(result)
        let versions = try #require(root["versions"] as? [[String: Any]])
        let customVersion = try #require(versions.first { $0["id"] as? String == "little-switch" })
        #expect(customVersion["intelligence_presets"] == nil)
        let slugs = try #require(customVersion["slugs"] as? [String])
        let categories = root["categories"] as? [[String: Any]] ?? []
        // The desktop catalog consumer resolves preset-free version options
        // from categories whose default_model belongs to that version's slugs.
        let selectableModels = categories.compactMap { $0["default_model"] as? String }.filter(slugs.contains)
        #expect(selectableModels == ["local:small"])
        let selected = try #require(categories.first { $0["default_model"] as? String == "local:small" })
        #expect(selected["supported_models"] as? [String] == ["local:small"])
        #expect(selected["title"] as? String == "Local/Small")
        if existingCategories {
            #expect(
                categories.first as NSDictionary? == ["category": "native", "default_model": "native", "unknown": true]
                    as NSDictionary)
        }
    }
}
