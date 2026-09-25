import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTCatalogTests {
    @Test func versionPickerPreservesNativeCatalogAndPolicy() throws {
        let native = Data(
            #"""
            {"default_model_slug":"native","models":[{"slug":"native","title":"Native","extra":{"keep":true}}],
             "versions":[{"id":"native-version","slugs":["native"],
                          "intelligence_presets":[{"model_slug":"native","title":"Native"}]}],
             "workspace_model_policy":{"selection":{"model":"native"},"new_thread_precedence":"prefer_policy"}}
            """#.utf8)
        let expected = Data(
            #"""
            {"default_model_slug":"native","models":[{"slug":"native","title":"Native","extra":{"keep":true}},
             {"slug":"local:small","title":"Local/Small","description":"LittleSwitch","enabled_tools":[],
              "configurable_thinking_effort":false,"reasoning_type":"none"}],
             "versions":[{"id":"native-version","slugs":["native"],
                          "intelligence_presets":[{"model_slug":"native","title":"Native"}]},
                         {"id":"little-switch","display_text":"Local/Small","slugs":["local:small"]}],
             "categories":[{"category":"little-switch:local:small","default_model":"local:small",
                            "human_category_name":"Local/Small","human_category_short_name":"Local/Small",
                            "short_explainer":null,"supported_models":["local:small"],"tagline":null,"title":"Local/Small"}],
             "workspace_model_policy":{"selection":{"model":"native"},"new_thread_precedence":"prefer_policy"}}
            """#.utf8)

        let result = try ChatGPTCatalog.merge(
            nativeData: native, models: [ChatGPTCatalogModel(slug: "local:small", title: "Local/Small")])

        #expect(try chatJSONObject(result) as NSDictionary == chatJSONObject(expected) as NSDictionary)
    }

    @Test(arguments: [false, true])
    func categoryPickerRetainsBothSets(emptyVersions: Bool) throws {
        var native: [String: Any] = [
            "models": [["slug": "native", "enabled_tools": ["native-tool"]]],
            "categories": [["category": "native-category", "default_model": "native", "unknown": true]],
        ]
        if emptyVersions { native["versions"] = [Any]() }
        var expected = native
        expected["models"] = [
            ["slug": "native", "enabled_tools": ["native-tool"]],
            [
                "slug": "one", "title": "First", "description": "LittleSwitch", "enabled_tools": [String](),
                "configurable_thinking_effort": false, "reasoning_type": "none",
            ],
            [
                "slug": "two", "title": "Second", "description": "LittleSwitch", "enabled_tools": [String](),
                "configurable_thinking_effort": false, "reasoning_type": "none",
            ],
        ]
        expected["categories"] = [
            ["category": "native-category", "default_model": "native", "unknown": true],
            [
                "category": "little-switch:one", "default_model": "one", "human_category_name": "First",
                "human_category_short_name": "First", "short_explainer": NSNull(), "supported_models": ["one"],
                "tagline": NSNull(), "title": "First",
            ],
            [
                "category": "little-switch:two", "default_model": "two", "human_category_name": "Second",
                "human_category_short_name": "Second", "short_explainer": NSNull(), "supported_models": ["two"],
                "tagline": NSNull(), "title": "Second",
            ],
        ]
        let result = try ChatGPTCatalog.merge(
            nativeData: JSONSerialization.data(withJSONObject: native),
            models: [.init(slug: "one", title: "First"), .init(slug: "two", title: "Second")])
        #expect(try chatJSONObject(result) as NSDictionary == expected as NSDictionary)
    }

    @Test(arguments: [false, true], [false, true])
    func legacyPickerDoesNotIntroduceLanes(emptyVersions: Bool, emptyCategories: Bool) throws {
        var native: [String: Any] = ["models": [["slug": "native"]], "default_model_slug": "native"]
        if emptyVersions { native["versions"] = [Any]() }
        if emptyCategories { native["categories"] = [Any]() }
        var expected = native
        expected["models"] = [
            ["slug": "native"],
            [
                "slug": "local", "title": "Local", "description": "LittleSwitch", "enabled_tools": [String](),
                "configurable_thinking_effort": false, "reasoning_type": "none",
            ],
        ]
        let result = try ChatGPTCatalog.merge(
            nativeData: JSONSerialization.data(withJSONObject: native), models: [.init(slug: "local", title: "Local")])
        #expect(try chatJSONObject(result) as NSDictionary == expected as NSDictionary)
    }

    @Test(arguments: ["  {\"models\": []} \n", "not JSON", "[]", ""])
    func emptyManagedListIsByteExactPassthrough(native: String) throws {
        let data = Data(native.utf8)
        #expect(try ChatGPTCatalog.merge(nativeData: data, models: []) == data)
    }

    @Test(arguments: [
        "not JSON", "[]", "null", "{}", #"{"models":null}"#, #"{"models":{}}"#,
        #"{"models":[null]}"#, #"{"models":[{}]}"#, #"{"models":[{"slug":0}]}"#,
        #"{"models":[{"slug":""}]}"#, #"{"models":[],"versions":null}"#,
        #"{"models":[],"versions":{}}"#, #"{"models":[],"categories":null}"#,
        #"{"models":[],"categories":"invalid"}"#,
        #"{"models":[],"versions":[{"id":"native"}],"categories":false}"#,
    ])
    func malformedNativeCatalogIsRejected(native: String) {
        #expect(throws: ChatGPTCatalog.MergeError.invalidNativeCatalog) {
            try ChatGPTCatalog.merge(nativeData: Data(native.utf8), models: [.init(slug: "local", title: "Local")])
        }
    }

    @Test(arguments: ["", " ", "\n", " local", "local ", "local\n", "\u{00A0}local"], [false, true])
    func invalidManagedFieldsAreRejected(value: String, invalidTitle: Bool) {
        let model = ChatGPTCatalogModel(slug: invalidTitle ? "local" : value, title: invalidTitle ? value : "Local")
        #expect(throws: ChatGPTCatalog.MergeError.invalidManagedModel) {
            try ChatGPTCatalog.merge(nativeData: Data(#"{"models":[]}"#.utf8), models: [model])
        }
    }

    @Test(arguments: ["local", "LOCAL", "Local"])
    func duplicateManagedSlugsAreRejected(slug: String) {
        #expect(throws: ChatGPTCatalog.MergeError.duplicateModelSlug) {
            try ChatGPTCatalog.merge(
                nativeData: Data(#"{"models":[]}"#.utf8),
                models: [.init(slug: "local", title: "First"), .init(slug: slug, title: "Second")])
        }
    }

    @Test(arguments: ["native", "NATIVE", "Native"])
    func nativeSlugCollisionIsRejected(slug: String) {
        #expect(throws: ChatGPTCatalog.MergeError.duplicateModelSlug) {
            try ChatGPTCatalog.merge(
                nativeData: Data(#"{"models":[{"slug":"native"}]}"#.utf8),
                models: [.init(slug: slug, title: "Managed")])
        }
    }

    @Test(arguments: [
        #"{"models":[],"versions":[{"id":"little-switch"}]}"#,
        #"{"models":[],"versions":[{"id":"LITTLE-SWITCH"}]}"#,
        #"{"models":[],"categories":[{"category":"little-switch:local"}]}"#,
        #"{"models":[],"categories":[{"category":"LITTLE-SWITCH:LOCAL"}]}"#,
        #"{"models":[],"versions":[{"id":"native"}],"categories":[{"category":"LITTLE-SWITCH:LOCAL"}]}"#,
    ])
    func introducedIdentifierCollisionIsRejected(native: String) {
        #expect(throws: ChatGPTCatalog.MergeError.identifierCollision) {
            try ChatGPTCatalog.merge(nativeData: Data(native.utf8), models: [.init(slug: "local", title: "Local")])
        }
    }

    @Test func secondMergeRejectsAlreadyManagedSlug() throws {
        let models = [ChatGPTCatalogModel(slug: "local", title: "Local")]
        let first = try ChatGPTCatalog.merge(nativeData: Data(#"{"models":[]}"#.utf8), models: models)
        #expect(throws: ChatGPTCatalog.MergeError.duplicateModelSlug) {
            try ChatGPTCatalog.merge(nativeData: first, models: models)
        }
    }

    @Test func versionPickerPreservesCategoriesUnknownMetadataAndUnicode() throws {
        let native = Data(
            #"""
            {"models":[{"slug":"native","attachments":{"enabled":true},"unknown":[null,1,false]}],
             "versions":[null,{"id":"native-version","opaque":{"a":"b"}}],
             "categories":[{"category":"native-category","opaque":[true,42]}],
             "unknown_root":{"unicode":"Étoile 星","number":1234567890123456789}}
            """#.utf8)
        let expected = Data(
            #"""
            {"models":[{"slug":"native","attachments":{"enabled":true},"unknown":[null,1,false]},
                        {"slug":"local:\"a\\b","title":"Étoile 星 🚀","description":"LittleSwitch",
                         "enabled_tools":[],"configurable_thinking_effort":false,"reasoning_type":"none"},
                        {"slug":"other","title":"Other","description":"LittleSwitch",
                         "enabled_tools":[],"configurable_thinking_effort":false,"reasoning_type":"none"}],
             "versions":[null,{"id":"native-version","opaque":{"a":"b"}},
                         {"id":"little-switch","display_text":"Étoile 星 🚀","slugs":["local:\"a\\b","other"]}],
             "categories":[{"category":"native-category","opaque":[true,42]},
                           {"category":"little-switch:local:\"a\\b","default_model":"local:\"a\\b",
                            "human_category_name":"Étoile 星 🚀","human_category_short_name":"Étoile 星 🚀",
                            "short_explainer":null,"supported_models":["local:\"a\\b"],"tagline":null,"title":"Étoile 星 🚀"},
                           {"category":"little-switch:other","default_model":"other",
                            "human_category_name":"Other","human_category_short_name":"Other",
                            "short_explainer":null,"supported_models":["other"],"tagline":null,"title":"Other"}],
             "unknown_root":{"unicode":"Étoile 星","number":1234567890123456789}}
            """#.utf8)
        let result = try ChatGPTCatalog.merge(
            nativeData: native,
            models: [.init(slug: #"local:"a\b"#, title: "Étoile 星 🚀"), .init(slug: "other", title: "Other")])
        #expect(try chatJSONObject(result) as NSDictionary == chatJSONObject(expected) as NSDictionary)
    }
}
