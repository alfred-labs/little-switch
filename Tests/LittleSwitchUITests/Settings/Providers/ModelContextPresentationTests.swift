import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Compact model capacity presentation")
struct ModelContextPresentationTests {
    @Test("A detected context has no manual declaration", arguments: [262_144, 1_000_000, 1_048_576])
    func detectedContextReplacesManualDraft(tokens: Int) throws {
        var draft = ModelContextDraft(
            model: DiscoveredModel(id: "model", detectedContextWindow: tokens, contextWindowOverride: 1_000_000)
        )

        #expect(!draft.allows1MOverride)
        #expect(!draft.declares1MManually)
        #expect(draft.overrideText.isEmpty)
        #expect(try ModelContextDraft.contextOverrides(from: [draft]).isEmpty)

        draft.declares1MManually = true
        #expect(!draft.declares1MManually)
        #expect(try draft.parsedOverride() == nil)
    }

    @Test("Forcing 1M never presents an unknown capacity as detected")
    func forcingUnknownCapacity() throws {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        let detectedCapacity = draft.capacityText

        draft.declares1MManually = true

        #expect(draft.capacityText == detectedCapacity)
        #expect(try ModelContextDraft.contextOverrides(from: [draft]) == ["unknown": 1_000_000])

        draft.declares1MManually = false
        #expect(draft.capacityText == detectedCapacity)
        #expect(try ModelContextDraft.contextOverrides(from: [draft]).isEmpty)
    }

    @Test("Detected capacities use exact, grouped token counts")
    func detectedCapacities() {
        for tokens in [262_144, 400_000, 1_000_000, 1_048_576] {
            let draft = ModelContextDraft(model: DiscoveredModel(id: "model", detectedContextWindow: tokens))
            #expect(draft.capacityText == tokens.formatted(.number))
        }
        let unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        #expect(unknown.capacityText == L10n.string("Not reported"))
    }

    @Test("Rows distinguish automatic, unavailable, and manual 1M")
    func claudeStates() {
        let models: [DiscoveredModel] = [
            DiscoveredModel(id: "large", detectedContextWindow: 1_048_576, contextWindowOverride: 200_000),
            DiscoveredModel(id: "boundary", detectedContextWindow: 1_000_000),
            DiscoveredModel(id: "below", detectedContextWindow: 999_999),
            DiscoveredModel(id: "small", detectedContextWindow: 262_144, contextWindowOverride: 1_000_000),
            DiscoveredModel(id: "unknown"),
            DiscoveredModel(id: "forced", contextWindowOverride: 1_000_000),
        ]
        #expect(
            models.map { ModelContextDraft(model: $0).claude1MState }
                == [.automatic, .automatic, .unavailable, .unavailable, .manual, .manual])
    }

    @Test("Saved declarations of at least 1M remain visibly enabled", arguments: [1_000_000, 1_048_576, 2_000_000])
    func savedDeclarations(tokens: Int) throws {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "unknown", contextWindowOverride: tokens))
        #expect(draft.declares1MManually)
        #expect(draft.capacityText == L10n.string("Not reported"))
        #expect(try draft.parsedOverride() == tokens)

        draft.declares1MManually = false
        #expect(try draft.parsedOverride() == nil)
    }

    @Test("Invalid overrides never present a plausible capacity")
    func invalidCapacity() {
        var draft = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        draft.overrideText = "invalid"
        #expect(draft.capacityText == L10n.string("Invalid override"))
    }
}
