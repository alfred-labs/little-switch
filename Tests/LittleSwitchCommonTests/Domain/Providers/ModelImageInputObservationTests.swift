import Foundation
import Testing

@testable import LittleSwitchCommon

@Suite("Model image input observation")
struct ModelImageInputObservationTests {
    @Test("Persistence roundtrips route identity, verdict, provenance and observation time")
    func roundtrip() throws {
        let observation = ModelImageInputObservation(
            key: ModelImageInputKey(
                providerID: UUID(),
                modelID: "Exact-ID",
                wire: .chatCompletions,
                endpoint: "https://provider.example/v1/chat/completions"),
            verdict: .unsupported,
            source: .providerRejection,
            observedAt: Date(timeIntervalSince1970: 100))
        let encoded = try JSONEncoder().encode(observation)
        #expect(try JSONDecoder().decode(ModelImageInputObservation.self, from: encoded) == observation)
    }
}
