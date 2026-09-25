import Foundation
import Testing

@testable import LittleSwitchCommon

struct ChatGPTConfigurationTests {
    @Test func selectionUsesStableIdentityAndNeverFallsBack() {
        var provider = Provider(
            name: "Renamed",
            baseURL: "https://example.invalid",
            authMode: .none,
            models: [DiscoveredModel(id: "first"), DiscoveredModel(id: "chosen")])
        let configuration = ChatGPTConfiguration(model: ModelMapping(providerID: provider.id, modelID: "chosen"))
        #expect(configuration.resolvedModel(in: [provider])?.model.id == "chosen")
        #expect(ChatGPTConfiguration().resolvedModel(in: [provider]) == nil)
        #expect(configuration.resolvedModel(in: []) == nil)
        #expect(configuration.resolvedModel(in: [provider, provider]) == nil)
        provider.models.append(DiscoveredModel(id: "chosen"))
        #expect(configuration.resolvedModel(in: [provider]) == nil)
        provider.models = [DiscoveredModel(id: "first")]
        #expect(configuration.resolvedModel(in: [provider]) == nil)
    }

    @Test func selectedIdentitySurvivesPersistence() throws {
        let data = Data(
            #"{"connected":true,"model":{"providerID":"00000000-0000-0000-0000-000000000001","modelID":"chat"}}"#.utf8)
        let configuration = try JSONDecoder().decode(ChatGPTConfiguration.self, from: data)
        let encoded = try JSONEncoder().encode(configuration)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let model = try #require(object["model"] as? [String: String])
        #expect(model == ["providerID": "00000000-0000-0000-0000-000000000001", "modelID": "chat"])
    }

    @Test func legacyConnectionDecodesWithoutAnInventedSelection() throws {
        let configuration = try JSONDecoder().decode(ChatGPTConfiguration.self, from: Data(#"{"connected":true}"#.utf8))
        #expect(configuration.connected)
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any])
        #expect(object["model"] == nil)
    }
}
