import Foundation
import Testing

@testable import LittleSwitchCore

extension CodexAutoReviewTests {
    @Test("Legacy catalog reconstruction changes only managed routing metadata")
    func legacyCatalogPreservesContent() throws {
        let current = Data(
            #"""
            {"future":true,"models":[
              {"slug":"local/task","description":"little-switch-auto-review","auto_review_model_override":"little-switch-auto-review","priority":0},
              {"slug":"gpt-native","auto_review_model_override":"native-special","priority":1},
              {"slug":"codex-auto-review","display_name":"OpenAI reviewer","priority":2},
              {"slug":"little-switch-auto-review","display_name":"little-switch-auto-review","auto_review_model_override":"little-switch-auto-review","priority":3}
            ]}
            """#.utf8)
        let expected = Data(
            #"""
            {"future":true,"models":[
              {"slug":"local/task","description":"little-switch-auto-review","auto_review_model_override":"codex-auto-review","priority":0},
              {"slug":"gpt-native","auto_review_model_override":"native-special","priority":1},
              {"slug":"codex-auto-review","display_name":"codex-auto-review","auto_review_model_override":"codex-auto-review","priority":2}
            ]}
            """#.utf8)

        let actual = try CodexCatalog.legacyAutoReviewData(current)
        #expect(
            try JSONSerialization.jsonObject(with: actual) as? NSDictionary
                == JSONSerialization.jsonObject(with: expected) as? NSDictionary)
        #expect(try CodexCatalog.legacyAutoReviewData(actual) == actual)
    }

    @Test("Malformed legacy catalog input is rejected", arguments: ["not-json", "[]", "{}", #"{"models":null}"#])
    func malformedLegacyCatalog(input: String) {
        #expect(throws: CodexCatalog.Error.empty) {
            try CodexCatalog.legacyAutoReviewData(Data(input.utf8))
        }
    }
}
