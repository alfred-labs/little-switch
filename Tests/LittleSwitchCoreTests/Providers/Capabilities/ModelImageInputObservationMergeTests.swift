import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image observation merge")
struct ModelImageInputObservationMergeTests {
    @Test("Merge keeps newest evidence only for current route keys in stable order")
    func latestValidKeys() throws {
        let provider = Provider(name: "Example", baseURL: "https://provider.example", authMode: .none)
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        let deletedKey = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "deleted", wire: .responses)
        let old = ModelImageInputObservation(
            key: key, verdict: .verified, source: .visualProbe, observedAt: Date(timeIntervalSince1970: 1))
        let newest = ModelImageInputObservation(
            key: key, verdict: .unsupported, source: .providerRejection, observedAt: Date(timeIntervalSince1970: 2))
        let removed = ModelImageInputObservation(
            key: deletedKey,
            verdict: .unsupported,
            source: .providerRejection,
            observedAt: Date(timeIntervalSince1970: 3))
        #expect(
            ModelImageInputObservationMerge.merge(existing: [old, removed], incoming: [newest], validKeys: [key]) == [
                newest
            ])
        #expect(
            ModelImageInputObservationMerge.merge(existing: [newest], incoming: [old], validKeys: [key]) == [newest])
        #expect(ModelImageInputObservationMerge.merge(existing: [newest], incoming: [], validKeys: [key]) == [newest])
        #expect(ModelImageInputObservationMerge.merge(existing: [newest], incoming: [], validKeys: []).isEmpty)
        #expect(
            ModelImageInputObservationMerge.merge(
                existing: [newest, removed], incoming: [], validKeys: [key, deletedKey])
                == [removed, newest])
    }
}
