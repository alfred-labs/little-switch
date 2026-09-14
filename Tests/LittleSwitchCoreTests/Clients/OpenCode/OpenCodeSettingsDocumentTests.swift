import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode settings document")
struct OpenCodeSettingsDocumentTests {
    @Test("Activation creates only the owned paths in a missing document")
    func missingDocumentActivation() throws {
        let activated = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        let root = try object(activated)
        let providers = try providerObject(root)

        #expect(Set(root.keys) == ["model", "provider"])
        #expect(root["model"] as? String == managed.model)
        #expect(Set(providers.keys) == [OpenCodeManagedSettings.providerID])
        #expect(jsonEqual(providers[OpenCodeManagedSettings.providerID], try managedProviderObject))
        #expect(try OpenCodeSettingsDocument.isManaged(activated, managed: managed))
    }

    @Test("Activation preserves unrelated settings and providers")
    func activationPreservesUnrelatedValues() throws {
        let original = Data(
            #"{"$schema":"https://opencode.ai/config.json","model":"old/model","provider":{"keep":{"npm":"keep"},"little-switch":{"name":"old"}},"small_model":"keep/small","theme":"dark"}"#
                .utf8
        )

        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)
        let root = try object(activated)
        let providers = try providerObject(root)

        #expect(root["$schema"] as? String == "https://opencode.ai/config.json")
        #expect(root["small_model"] as? String == "keep/small")
        #expect(root["theme"] as? String == "dark")
        #expect(jsonEqual(providers["keep"], ["npm": "keep"]))
        #expect(root["model"] as? String == managed.model)
        #expect(jsonEqual(providers[OpenCodeManagedSettings.providerID], try managedProviderObject))
    }

    @Test("Restoration restores unchanged owned values and keeps external providers")
    func unchangedRestore() throws {
        let original = Data(
            #"{"model":"old/model","provider":{"keep":{"npm":"keep"},"little-switch":{"name":"old"}},"theme":"dark"}"#
                .utf8
        )
        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)
        var current = try object(activated)
        var providers = try providerObject(current)
        providers["external"] = ["npm": "external"]
        current["provider"] = providers
        current["theme"] = "light"

        let restored = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: try encode(current),
                original: original,
                managed: managed
            )
        )
        let root = try object(restored)
        let restoredProviders = try providerObject(root)

        #expect(root["model"] as? String == "old/model")
        #expect(root["theme"] as? String == "light")
        #expect(jsonEqual(restoredProviders["keep"], ["npm": "keep"]))
        #expect(jsonEqual(restoredProviders["external"], ["npm": "external"]))
        #expect(jsonEqual(restoredProviders[OpenCodeManagedSettings.providerID], ["name": "old"]))
    }

    @Test("Restoration preserves each externally changed owned path independently")
    func driftRestore() throws {
        let original = Data(
            #"{"model":"old/model","provider":{"little-switch":{"name":"old"}}}"#.utf8
        )
        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)

        var modelDrift = try object(activated)
        modelDrift["model"] = "manual/model"
        let modelDriftRestored = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: try encode(modelDrift),
                original: original,
                managed: managed
            )
        )
        let modelDriftRoot = try object(modelDriftRestored)
        #expect(modelDriftRoot["model"] as? String == "manual/model")
        #expect(
            jsonEqual(
                try providerObject(modelDriftRoot)[OpenCodeManagedSettings.providerID],
                ["name": "old"]
            )
        )

        var providerDrift = try object(activated)
        var providers = try providerObject(providerDrift)
        providers[OpenCodeManagedSettings.providerID] = ["name": "manual"]
        providerDrift["provider"] = providers
        let providerDriftRestored = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: try encode(providerDrift),
                original: original,
                managed: managed
            )
        )
        let providerDriftRoot = try object(providerDriftRestored)
        #expect(providerDriftRoot["model"] as? String == "old/model")
        #expect(
            jsonEqual(
                try providerObject(providerDriftRoot)[OpenCodeManagedSettings.providerID],
                ["name": "manual"]
            )
        )
    }

    @Test("Restoration removes containers and documents only when empty")
    func absentOriginalRestore() throws {
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)
        let restored = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: activated,
                original: original,
                managed: managed
            )
        )
        let restoredRoot = try object(restored)
        #expect(restoredRoot.count == 1)
        #expect(restoredRoot["theme"] as? String == "dark")

        let created = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        #expect(
            try OpenCodeSettingsDocument.restoring(
                current: created,
                original: nil,
                managed: managed
            ) == nil
        )

        var externallyExtended = try object(created)
        externallyExtended["theme"] = "light"
        let extendedRestore = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: try encode(externallyExtended),
                original: nil,
                managed: managed
            )
        )
        let extendedRoot = try object(extendedRestore)
        #expect(extendedRoot.count == 1)
        #expect(extendedRoot["theme"] as? String == "light")
    }

    @Test("An externally deleted document stays deleted")
    func externalDeletion() throws {
        #expect(
            try OpenCodeSettingsDocument.restoring(
                current: nil,
                original: Data(#"{"theme":"dark"}"#.utf8),
                managed: managed
            ) == nil
        )
        #expect(!(try OpenCodeSettingsDocument.isManaged(nil, managed: managed)))
    }

    @Test("Managed detection requires exact equality for both owned paths")
    func exactManagedDetection() throws {
        let activated = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        var wrongModel = try object(activated)
        wrongModel["model"] = "manual/model"
        #expect(
            !(try OpenCodeSettingsDocument.isManaged(
                try encode(wrongModel),
                managed: managed
            ))
        )

        var wrongProvider = try object(activated)
        var providers = try providerObject(wrongProvider)
        var provider = try #require(
            providers[OpenCodeManagedSettings.providerID] as? [String: Any]
        )
        provider["extra"] = true
        providers[OpenCodeManagedSettings.providerID] = provider
        wrongProvider["provider"] = providers
        #expect(
            !(try OpenCodeSettingsDocument.isManaged(
                try encode(wrongProvider),
                managed: managed
            ))
        )

        var missingProvider = try object(activated)
        missingProvider.removeValue(forKey: "provider")
        #expect(
            !(try OpenCodeSettingsDocument.isManaged(
                try encode(missingProvider),
                managed: managed
            ))
        )
    }

    @Test("Invalid document shapes fail explicitly")
    func invalidDocuments() {
        #expect(throws: OpenCodeSettingsDocument.Error.invalidUTF8) {
            try OpenCodeSettingsDocument.activating(Data([0xFF]), managed: managed)
        }
        #expect(throws: OpenCodeSettingsDocument.Error.invalidJSON) {
            try OpenCodeSettingsDocument.activating(Data("{".utf8), managed: managed)
        }
        #expect(throws: OpenCodeSettingsDocument.Error.nonObjectRoot) {
            try OpenCodeSettingsDocument.activating(Data("[]".utf8), managed: managed)
        }
        #expect(throws: OpenCodeSettingsDocument.Error.nonObjectProvider) {
            try OpenCodeSettingsDocument.activating(
                Data(#"{"provider":"invalid"}"#.utf8),
                managed: managed
            )
        }
    }

    private var managed: OpenCodeManagedSettings {
        OpenCodeManagedSettings(
            model: "little-switch/little-switch-provider-model",
            provider: OpenCodeManagedProvider(
                npm: "@ai-sdk/openai",
                name: "LittleSwitch",
                options: OpenCodeManagedProviderOptions(
                    baseURL: "http://127.0.0.1:11436/v1",
                    apiKey: "little-switch"
                ),
                models: [
                    "little-switch-provider-model": OpenCodeManagedModel(
                        name: "Provider / model",
                        limit: OpenCodeManagedModelLimit(context: 128_000, output: 8_192)
                    )
                ]
            )
        )
    }

    private var managedProviderObject: [String: Any] {
        get throws {
            try #require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(managed.provider))
                    as? [String: Any]
            )
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func providerObject(_ root: [String: Any]) throws -> [String: Any] {
        try #require(root["provider"] as? [String: Any])
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func jsonEqual(_ left: Any?, _ right: Any?) -> Bool {
        guard let left, let right else {
            return left == nil && right == nil
        }
        let leftData = try? JSONSerialization.data(
            withJSONObject: ["value": left],
            options: [.sortedKeys]
        )
        let rightData = try? JSONSerialization.data(
            withJSONObject: ["value": right],
            options: [.sortedKeys]
        )
        return leftData == rightData
    }
}
