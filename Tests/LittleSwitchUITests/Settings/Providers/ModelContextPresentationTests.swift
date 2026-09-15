import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Compact model capacity presentation")
struct ModelContextPresentationTests {
    @Test("Detected capacities stay exact without repeating the same value")
    func detectedCapacities() {
        for tokens in [262_144, 400_000, 1_000_000] {
            let draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: tokens))
            #expect([draft.capacityText, draft.capacityNote] == [ModelContextDraft.format(tokens), nil])
        }
        let unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        #expect([unknown.capacityText, unknown.capacityNote] == [L10n.string("Unknown"), nil])
    }

    @Test("Manual capacities expose their difference from discovery")
    func manualCapacities() {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: 400_000))
        draft.overrideText = "200K"
        #expect(
            [draft.capacityText, draft.capacityNote]
                == [
                    ModelContextDraft.format(200_000),
                    L10n.string("Detected \(ModelContextDraft.format(400_000))"),
                ]
        )
        draft.overrideText = "400K"
        #expect(
            [draft.capacityText, draft.capacityNote]
                == [ModelContextDraft.format(400_000), nil]
        )

        var unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        unknown.declares1MManually = true
        #expect(
            [unknown.capacityText, unknown.capacityNote]
                == [ModelContextDraft.format(1_000_000), L10n.string("Manual override")]
        )
    }

    @Test("Invalid overrides never present a plausible capacity")
    func invalidCapacity() {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: 400_000))
        draft.overrideText = "invalid"
        #expect([draft.capacityText, draft.capacityNote] == [L10n.string("Invalid override"), nil])
    }
}
