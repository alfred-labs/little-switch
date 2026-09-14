import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model catalogue")
struct AppModelModelOptionsTests {
    @Test("Exposed models group under the provider that serves them")
    func codexExposureGrouping() {
        let localID = UUID()
        let remoteID = UUID()
        let emptyID = UUID()
        let configuration = AppConfiguration(
            providers: [
                Provider(
                    id: localID,
                    name: "ollama",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: "qwen"), DiscoveredModel(id: "deepseek")]
                ),
                Provider(
                    id: emptyID,
                    name: "unreachable",
                    baseURL: "https://example.invalid",
                    authMode: .none,
                    models: []
                ),
                Provider(
                    id: remoteID,
                    name: "z.ai",
                    baseURL: "https://api.z.ai/api/anthropic",
                    authMode: .bearer,
                    models: [DiscoveredModel(id: "glm-5.3")]
                ),
            ]
        )
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))

        let groups = model.codexExposureGroups

        #expect(groups.map(\.providerName) == ["ollama", "z.ai"])
        #expect(groups.map(\.id) == [localID, remoteID])
        #expect(groups[0].options.map(\.modelID) == ["deepseek", "qwen"])
        #expect(groups[1].options.map(\.modelID) == ["glm-5.3"])
        #expect(model.codexExposureGroups.flatMap(\.options) == model.modelOptions)
    }
}
