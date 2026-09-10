import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode model capabilities")
struct OpenCodeModelCapabilitiesTests {
    @Test("Image inputs follow the gateway policy, including unknown models and explicit overrides")
    func imageInputs() throws {
        try expectInput(["text", "image"], detected: nil)
        try expectInput(["text", "image"], detected: true)
        try expectInput(["text"], detected: false)
        try expectInput(["text", "image"], detected: false, override: .enabled)
        try expectInput(["text"], detected: true, override: .disabled)
    }

    @Test("Legacy model signatures retain absent capabilities when decoded and restored")
    func legacyModels() throws {
        let data = Data(#"{"name":"Legacy","limit":{"output":8192}}"#.utf8)
        let legacy = try JSONDecoder().decode(OpenCodeManagedModel.self, from: data)
        let encoded = try JSONEncoder().encode(legacy)

        let expected = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let actual = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)

        #expect(actual == expected)
    }

    private func expectInput(
        _ input: [String],
        detected: Bool?,
        override: ProviderImageInputOverride? = nil
    ) throws {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:9000",
            authMode: .none,
            models: [DiscoveredModel(id: "model", supportsImageInput: detected)],
            imageInputOverride: override
        )
        let managed = try OpenCodeManagedSettings.resolve(
            providers: [provider],
            codex: .disconnected,
            configuration: .disconnected
        )
        let data = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let providers = try #require(root["provider"] as? [String: Any])
        let entry = try #require(providers["little-switch"] as? [String: Any])
        let models = try #require(entry["models"] as? [String: Any])
        let model = try #require(models["local/model"] as? NSDictionary)
        let expected: NSDictionary = [
            "name": "Local/model",
            "modalities": ["input": input, "output": ["text"]],
        ]

        #expect(model == expected)
    }
}
