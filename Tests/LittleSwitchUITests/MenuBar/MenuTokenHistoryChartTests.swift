import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Shared menu token history chart")
struct MenuTokenHistoryChartTests {
    private let points = [0, 100, 200, 50]

    private var days: [GatewayUsageStatsPresentation.DayDetail] {
        points.indices.map {
            GatewayUsageStatsPresentation.DayDetail(
                id: "day-\($0)",
                label: "Day \($0 + 1)"
            )
        }
    }

    @Test("VoiceOver reads the series and adjusts the selected day within its bounds")
    func accessibilityAdjustment() async throws {
        var selection: Int?
        func content() -> MenuTokenHistoryChart {
            chart(selection: Binding(get: { selection }, set: { selection = $0 }))
        }
        let host = MenuControlTestHost(content(), height: GatewayOverviewLayout.chartHeight)
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                == "4 days, 350 tokens"
        )
        #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformIncrement())
        #expect(selection == 3)
        for expected in [2, 1, 0, 0] {
            #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformDecrement())
            #expect(selection == expected)
            host.hosting.rootView = content()
            host.render()
            #expect(
                try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                    == "\(days[expected].label), \(points[expected]) tokens"
            )
        }
        for expected in [1, 2, 3, 3] {
            #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformIncrement())
            #expect(selection == expected)
        }
    }

    @Test("Native pointer movement selects a day and leaving restores the resting caption")
    func pointerSelection() async throws {
        var selection: Int?
        func content() -> MenuTokenHistoryChart {
            chart(selection: Binding(get: { selection }, set: { selection = $0 }))
        }
        let host = MenuControlTestHost(content(), height: GatewayOverviewLayout.chartHeight)
        defer { host.close() }
        host.window.appearance = NSAppearance(named: .darkAqua)
        try await host.activateAccessibility()
        let tracking = try host.nativeView(of: MouseLocationReader.TrackingView.self)
        #expect(tracking.bounds.width > 0)
        let location = tracking.convert(
            NSPoint(x: tracking.bounds.width * 0.3, y: tracking.bounds.midY),
            to: nil
        )
        let move = try #require(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: host.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
        tracking.mouseMoved(with: move)
        #expect(selection == 1)
        host.hosting.rootView = content()
        host.render()
        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                == "Day 2, 100 tokens"
        )

        let exit = try #require(
            NSEvent.enterExitEvent(
                with: .mouseExited,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: host.window.windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            )
        )
        tracking.mouseExited(with: exit)
        #expect(selection == nil)
        host.hosting.rootView = content()
        host.render()
        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                == "4 days, 350 tokens"
        )
    }

    @Test("A quiet history remains an accessible zero-token series")
    func quietHistory() async throws {
        let host = MenuControlTestHost(
            MenuTokenHistoryChart(
                points: [0, 0, 0, 0],
                days: days,
                axisLabels: ["Day 1", "Day 2", "Day 4"],
                periodLabel: "4 days",
                tokenTotal: "0",
                accessibilityValue: "4 days, 0 tokens",
                hoveredIndex: .constant(nil)
            ),
            height: GatewayOverviewLayout.chartHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()
        // AppKit exposes an adjustable control's spoken text through
        // AXValueDescription rather than a numeric AXValue.
        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                == "4 days, 0 tokens"
        )
    }

    @Test("An empty series keeps no selected day when VoiceOver adjusts it")
    func emptyHistory() async throws {
        var selection: Int? = 0
        let host = MenuControlTestHost(
            MenuTokenHistoryChart(
                points: [],
                days: [],
                axisLabels: [],
                periodLabel: "0 days",
                tokenTotal: "0",
                accessibilityValue: "0 days, 0 tokens",
                hoveredIndex: Binding(get: { selection }, set: { selection = $0 })
            ),
            height: GatewayOverviewLayout.chartHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformIncrement())
        #expect(selection == nil)
        #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformDecrement())
        #expect(selection == nil)
        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription() == "0 days, 0 tokens")
        #expect(host.hosting.fittingSize.height == GatewayOverviewLayout.chartHeight)
    }

    private func chart(selection: Binding<Int?>) -> MenuTokenHistoryChart {
        let label = selection.wrappedValue.map { days[$0].label } ?? "4 days"
        let total = selection.wrappedValue.map { "\(points[$0])" } ?? "350"
        return MenuTokenHistoryChart(
            points: points,
            days: days,
            axisLabels: ["Day 1", "Day 2", "Day 4"],
            periodLabel: label,
            tokenTotal: total,
            accessibilityValue: "\(label), \(total) tokens",
            hoveredIndex: selection
        )
    }
}
