import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Compact model capacity presentation")
struct ModelContextPresentationTests {
    @Test("Detected capacities stay exact without repeating the same value")
    func detectedCapacities() {
        for (tokens, label) in [(262_144, "262144"), (400_000, "400K"), (1_000_000, "1M")] {
            let draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: tokens))
            #expect([draft.capacityText, draft.capacityNote] == [label, nil])
        }
        let unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        #expect([unknown.capacityText, unknown.capacityNote] == ["Unknown", nil])
    }

    @Test("Manual capacities expose their difference from discovery")
    func manualCapacities() {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: 400_000))
        draft.overrideText = "200K"
        #expect([draft.capacityText, draft.capacityNote] == ["200K", "Detected 400K"])
        draft.overrideText = "400K"
        #expect([draft.capacityText, draft.capacityNote] == ["400K", nil])

        var unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        unknown.declares1MManually = true
        #expect([unknown.capacityText, unknown.capacityNote] == ["1M", "Manual override"])
    }

    @Test("Invalid overrides never present a plausible capacity")
    func invalidCapacity() {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: 400_000))
        draft.overrideText = "invalid"
        #expect([draft.capacityText, draft.capacityNote] == ["Invalid override", nil])
    }
}
