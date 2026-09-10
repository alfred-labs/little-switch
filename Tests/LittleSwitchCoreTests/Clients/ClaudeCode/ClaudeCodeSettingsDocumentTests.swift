import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code settings document")
struct ClaudeCodeSettingsDocumentTests {
    @Test("Activation preserves unrelated JSON and replaces only managed values")
    func activation() throws {
        let originalJSON =
            #"{"array":[1,"two",false,null],"env":{"ANTHROPIC_BASE_URL":"old","KEEP":7},"fraction":1.5,"nested":{"enabled":true},"theme":"dark"}"#
        let original = Data(originalJSON.utf8)

        let activated = try ClaudeCodeSettingsDocument.activating(
            original,
            managed: managed
        )
        let root = try object(activated)
        let environment = try #require(root["env"] as? [String: Any])

        #expect(root["model"] as? String == managed.model)
        #expect(root["theme"] as? String == "dark")
        #expect((root["nested"] as? [String: Bool]) == ["enabled": true])
        #expect((root["fraction"] as? NSNumber)?.doubleValue == 1.5)
        #expect((root["array"] as? [Any])?.count == 4)
        #expect((environment["KEEP"] as? NSNumber)?.intValue == 7)
        for (key, value) in managed.environment {
            #expect(environment[key] as? String == value)
        }
        #expect(try ClaudeCodeSettingsDocument.isManaged(activated, managed: managed))
    }

    @Test("Restoration restores unchanged managed paths and keeps unrelated edits")
    func unchangedRestore() throws {
        let original = Data(
            #"{"env":{"ANTHROPIC_BASE_URL":"old","KEEP":"yes"},"model":"old-model","theme":"dark"}"#.utf8
        )
        let activated = try ClaudeCodeSettingsDocument.activating(original, managed: managed)
        var current = try object(activated)
        current["theme"] = "light"

        let restored = try #require(
            try ClaudeCodeSettingsDocument.restoring(
                current: try encode(current),
                original: original,
                managed: managed
            )
        )

        let root = try object(restored)
        let environment = try #require(root["env"] as? [String: Any])
        #expect(root["model"] as? String == "old-model")
        #expect(root["theme"] as? String == "light")
        #expect(environment["ANTHROPIC_BASE_URL"] as? String == "old")
        #expect(environment["KEEP"] as? String == "yes")
        for key in managed.environment.keys where key != "ANTHROPIC_BASE_URL" {
            #expect(environment[key] == nil)
        }
    }

    @Test("Restoration preserves every externally changed managed path")
    func driftRestore() throws {
        let original = Data(#"{"env":{"KEEP":"yes"},"model":"old-model"}"#.utf8)
        let activated = try ClaudeCodeSettingsDocument.activating(original, managed: managed)
        var current = try object(activated)
        current["model"] = "manual-model"
        var environment = try #require(current["env"] as? [String: Any])
        for key in managed.environment.keys {
            environment[key] = "manual-\(key)"
        }
        current["env"] = environment

        let restored = try #require(
            try ClaudeCodeSettingsDocument.restoring(
                current: try encode(current),
                original: original,
                managed: managed
            )
        )
        let root = try object(restored)
        let restoredEnvironment = try #require(root["env"] as? [String: Any])

        #expect(root["model"] as? String == "manual-model")
        #expect(restoredEnvironment["KEEP"] as? String == "yes")
        for key in managed.environment.keys {
            #expect(restoredEnvironment[key] as? String == "manual-\(key)")
        }
        #expect(!(try ClaudeCodeSettingsDocument.isManaged(restored, managed: managed)))
    }

    @Test("An originally absent settings file is removed when no external data remains")
    func absentOriginal() throws {
        let activated = try ClaudeCodeSettingsDocument.activating(nil, managed: managed)

        #expect(
            try ClaudeCodeSettingsDocument.restoring(
                current: activated,
                original: nil,
                managed: managed
            ) == nil
        )

        var current = try object(activated)
        current["theme"] = "light"
        let restored = try #require(
            try ClaudeCodeSettingsDocument.restoring(
                current: try encode(current),
                original: nil,
                managed: managed
            )
        )
        let restoredObject = try object(restored)
        #expect(restoredObject.count == 1)
        #expect(restoredObject["theme"] as? String == "light")
    }

    @Test("An externally deleted settings file stays deleted")
    func externalDeletion() throws {
        #expect(
            try ClaudeCodeSettingsDocument.restoring(
                current: nil,
                original: Data(#"{"theme":"dark"}"#.utf8),
                managed: managed
            ) == nil
        )
        #expect(!(try ClaudeCodeSettingsDocument.isManaged(nil, managed: managed)))
    }

    @Test("Restoration removes an env object that was originally absent and is empty")
    func removesEmptyEnvironment() throws {
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let activated = try ClaudeCodeSettingsDocument.activating(original, managed: managed)
        let restored = try #require(
            try ClaudeCodeSettingsDocument.restoring(
                current: activated,
                original: original,
                managed: managed
            )
        )

        let restoredObject = try object(restored)
        #expect(restoredObject.count == 1)
        #expect(restoredObject["theme"] as? String == "dark")
    }

    @Test("Invalid document shapes fail explicitly")
    func invalidDocuments() {
        #expect(throws: ClaudeCodeSettingsDocument.Error.invalidUTF8) {
            try ClaudeCodeSettingsDocument.activating(Data([0xFF]), managed: managed)
        }
        #expect(throws: ClaudeCodeSettingsDocument.Error.invalidJSON) {
            try ClaudeCodeSettingsDocument.activating(Data("{".utf8), managed: managed)
        }
        #expect(throws: ClaudeCodeSettingsDocument.Error.nonObjectRoot) {
            try ClaudeCodeSettingsDocument.activating(Data("[]".utf8), managed: managed)
        }
        #expect(throws: ClaudeCodeSettingsDocument.Error.nonObjectEnvironment) {
            try ClaudeCodeSettingsDocument.activating(
                Data(#"{"env":"invalid"}"#.utf8),
                managed: managed
            )
        }
    }

    @Test("Semantic comparison distinguishes JSON booleans from numbers")
    func semanticComparisonDistinguishesBooleansAndNumbers() throws {
        let boolean = Data(#"{"nested":{"value":true}}"#.utf8)
        let number = Data(#"{"nested":{"value":1}}"#.utf8)
        let reordered = Data(#"{ "nested" : { "value" : true } }"#.utf8)

        #expect(
            try ClaudeCodeSettingsDocument.semanticallyMatches(boolean, reordered)
        )
        #expect(
            !(try ClaudeCodeSettingsDocument.semanticallyMatches(boolean, number))
        )
    }

    @Test("Semantic comparison handles absent documents")
    func semanticComparisonHandlesAbsentDocuments() throws {
        let document = Data(#"{"theme":"dark"}"#.utf8)

        #expect(try ClaudeCodeSettingsDocument.semanticallyMatches(nil, nil))
        #expect(!(try ClaudeCodeSettingsDocument.semanticallyMatches(nil, document)))
        #expect(!(try ClaudeCodeSettingsDocument.semanticallyMatches(document, nil)))
    }

    private var managed: ClaudeCodeManagedSettings {
        ClaudeCodeManagedSettings(
            model: "claude-opus-5",
            environment: [
                "ANTHROPIC_BASE_URL": "http://127.0.0.1:11436",
                "ANTHROPIC_API_KEY": "",
                "ANTHROPIC_AUTH_TOKEN": "little-switch",
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5-20251001",
                "CLAUDE_CODE_USE_ANTHROPIC_AWS": "",
                "CLAUDE_CODE_USE_BEDROCK": "",
                "CLAUDE_CODE_USE_FOUNDRY": "",
                "CLAUDE_CODE_USE_MANTLE": "",
                "CLAUDE_CODE_USE_VERTEX": "",
                "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "",
                "DISABLE_TELEMETRY": "1",
                "DISABLE_ERROR_REPORTING": "1",
                "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
            ]
        )
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
