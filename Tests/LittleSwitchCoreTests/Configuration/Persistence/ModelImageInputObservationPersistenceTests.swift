import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image observation persistence")
struct ImageInputObservationPersistenceTests {
    @Test("Observation roundtrips through direct Provider and configuration v8")
    func roundtrip() throws {
        var provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        provider.imageInputObservations = [try observation(provider)]
        let configuration = AppConfiguration(providers: [provider])
        #expect(try JSONDecoder().decode(Provider.self, from: JSONEncoder().encode(provider)) == provider)
        #expect(
            try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration)) == configuration)
    }

    @Test("Missing or malformed derived observations never prevent loading provider settings")
    func compatibleDecoding() throws {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(provider)) as? [String: Any])
        object.removeValue(forKey: "imageInputObservations")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(Provider.self, from: oldData).imageInputObservations.isEmpty)
        object["imageInputObservations"] = "corrupt derived cache"
        #expect(
            try JSONDecoder().decode(Provider.self, from: JSONSerialization.data(withJSONObject: object)) == provider)
        let valid = try observation(provider)
        object["imageInputObservations"] = [
            ["verdict": "unsupported"],
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)),
        ]
        let decoded = try JSONDecoder().decode(Provider.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.imageInputObservations == [valid])
        var configuration = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfiguration(providers: [provider])))
                as? [String: Any])
        configuration["providers"] = [object]
        let loaded = try JSONDecoder().decode(
            AppConfiguration.self, from: JSONSerialization.data(withJSONObject: configuration))
        #expect(loaded.version == 9)
        #expect(loaded.providers.first?.imageInputObservations == [valid])
    }

    private func observation(_ provider: Provider) throws -> ModelImageInputObservation {
        ModelImageInputObservation(
            key: try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses),
            verdict: .verified,
            source: .visualProbe,
            observedAt: Date(timeIntervalSince1970: 1))
    }
}
