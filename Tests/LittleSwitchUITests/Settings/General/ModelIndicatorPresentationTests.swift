import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@Suite("Model indicator presentation")
struct ModelIndicatorPresentationTests {
    @Test("Every model indicator has a localized picker label")
    func everyModelIndicatorHasALocalizedPickerLabel() {
        #expect(ModelIndicator.none.localizedLabel.key == "None")
        #expect(ModelIndicator.swap.localizedLabel.key == "Swap ⇄")
        #expect(ModelIndicator.equilibrium.localizedLabel.key == "Equilibrium ⇌")
        #expect(ModelIndicator.routed.localizedLabel.key == "Routed ⇢")
        #expect(ModelIndicator.mapsTo.localizedLabel.key == "Maps to ↦")
    }
}
