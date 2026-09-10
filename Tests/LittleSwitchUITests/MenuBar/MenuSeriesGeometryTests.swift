import CoreGraphics
import Testing

@testable import LittleSwitchUI

@Suite("Menu series geometry")
struct MenuSeriesGeometryTests {
    @Test("The nearest slot tracks the pointer")
    func nearestSlot() {
        #expect(MenuSeriesGeometry.barIndex(at: 0, width: 300, dayCount: 30) == 0)
        #expect(MenuSeriesGeometry.barIndex(at: 150, width: 300, dayCount: 30) == 15)
        #expect(MenuSeriesGeometry.barIndex(at: 299.9, width: 300, dayCount: 30) == 29)
    }

    @Test("Moves past either end clamp to a real slot")
    func clamping() {
        #expect(MenuSeriesGeometry.barIndex(at: -5, width: 300, dayCount: 30) == 0)
        #expect(MenuSeriesGeometry.barIndex(at: 500, width: 300, dayCount: 30) == 29)
    }

    @Test("A degenerate frame names the first slot")
    func degenerateFrame() {
        #expect(MenuSeriesGeometry.barIndex(at: 10, width: 0, dayCount: 30) == 0)
        #expect(MenuSeriesGeometry.barIndex(at: 10, width: 300, dayCount: 0) == 0)
    }
}
