import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model context formatting")
struct AppModelContextFormattingTests {
    @Test("Context formatting covers unknown, exact, thousands, and millions")
    func completeModelContextFormatting() throws {
        var unknown = ModelContextDraft(model: DiscoveredModel(id: "unknown"))
        #expect(
            unknown.detail
                == L10n.string(
                    "Detected \(L10n.string("Unknown")) · Effective \(L10n.string("Unknown")) · Claude \(L10n.string("200K"))"
                )
        )

        unknown.overrideText = "123"
        #expect(
            unknown.detail
                == L10n.string(
                    "Detected \(L10n.string("Unknown")) · Effective \(ModelContextDraft.format(123)) · Claude \(L10n.string("200K"))"
                )
        )
        #expect(ModelContextDraft.format(123) == "123")
        #expect(ModelContextDraft.format(400_000) == L10n.string("\(400_000 / 1_000)K"))
        #expect(ModelContextDraft.format(2_000_000) == "2M")

        let overridden = ModelContextDraft(
            model: DiscoveredModel(id: "manual", contextWindowOverride: 1_000_000)
        )
        #expect(overridden.overrideText == "1M")
        #expect(overridden.declares1MManually)

        unknown.overrideText = "invalid"
        #expect(throws: ContextWindowInput.Error.self) {
            try ModelContextDraft.contextOverrides(from: [unknown])
        }
    }
}
