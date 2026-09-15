import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Codex catalog tool mode")
struct CodexCatalogToolModeTests {
    @Test("Managed models inherit Codex tool mode while native model metadata stays intact")
    func managedToolModeInheritance() throws {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Provider",
            baseURL: "https://provider.example/v1",
            authMode: .bearer,
            models: [DiscoveredModel(id: "coding-model")]
        )
        let native: [String: Any] = [
            "slug": "native-model", "tool_mode": "code_mode_only", "apply_patch_tool_type": "freeform",
            "priority": 9, "supported_in_api": true,
        ]
        let configuration = CodexConfiguration(
            defaultModel: ModelMapping(providerID: providerID, modelID: "coding-model"))
        let catalog = try CodexCatalog.make(providers: [provider], configuration: configuration)
        #expect(catalog.models.count == 2)
        let data = try CodexCatalog.encode(
            providers: [provider],
            configuration: configuration,
            nativeCatalogData: chatJSONData(["models": [native]])
        )
        let entries = try #require(chatJSONObject(data)["models"] as? [[String: Any]])
        let managed = entries.filter { $0["slug"] as? String != "native-model" }
        #expect(managed.count == 2)
        #expect(managed.contains { $0["slug"] as? String == CodexCatalog.managedAutoReviewModel })
        for entry in managed {
            #expect(entry["tool_mode"] == nil)
            #expect(entry["apply_patch_tool_type"] is NSNull)
        }
        var expectedNative = native
        expectedNative["supported_in_api"] = false
        expectedNative["priority"] = 1
        let receivedNative = try #require(entries.first { $0["slug"] as? String == "native-model" })
        #expect(NSDictionary(dictionary: receivedNative) == NSDictionary(dictionary: expectedNative))
    }
}
