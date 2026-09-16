import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Status menu switch drag destination")
struct StatusMenuSwitchDragTests {
    @Test("Only crossing the track midpoint changes the value", arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func destination(direction: LayoutDirection) {
        let cases: [Scenario] = [
            .init(isOn: false, translation: 24, expected: true, position: 12),
            .init(isOn: true, translation: -24, expected: false, position: 0),
            .init(isOn: false, translation: -6, expected: false, position: 0),
            .init(isOn: true, translation: 6, expected: true, position: 12),
            .init(isOn: false, translation: 0, expected: false, position: 0),
            .init(isOn: true, translation: 0, expected: true, position: 12),
            .init(isOn: false, translation: 5, expected: false, position: 5),
            .init(isOn: true, translation: -5, expected: true, position: 7),
            .init(isOn: false, translation: 6, expected: false, position: 6),
            .init(isOn: true, translation: -6, expected: false, position: 6),
            .init(isOn: false, translation: 7, expected: true, position: 7),
            .init(isOn: true, translation: -7, expected: false, position: 5),
        ]
        for scenario in cases {
            #expect(
                StatusMenuSwitchTrack.draggedValue(
                    isOn: scenario.isOn,
                    translation: scenario.translation * (direction == .leftToRight ? 1 : -1),
                    layoutDirection: direction
                ) == scenario.expected
            )
            #expect(
                StatusMenuSwitchTrack.thumbOffset(
                    isOn: scenario.isOn,
                    translation: scenario.translation * (direction == .leftToRight ? 1 : -1),
                    layoutDirection: direction
                ) == scenario.position * (direction == .leftToRight ? 1 : -1)
            )
        }
    }

    private struct Scenario {
        let isOn: Bool
        let translation: CGFloat
        let expected: Bool
        let position: CGFloat
    }
}
