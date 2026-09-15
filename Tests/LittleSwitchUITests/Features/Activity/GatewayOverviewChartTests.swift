import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Overview chart and metrics")
struct GatewayOverviewChartTests {
    @Test("Native day inspection updates the total and every metric together, then restores the aggregate")
    func pointerUpdatesCompletePeriod() async throws {
        let stats = Self.stats
        let host = host(stats)
        defer { host.close() }
        try await host.activateAccessibility()
        try await expectPeriod(stats.period(at: nil), in: host)
        let tracking = try host.nativeView(of: MouseLocationReader.TrackingView.self)
        let location = tracking.convert(
            NSPoint(x: tracking.bounds.width * 28.5 / 30, y: tracking.bounds.midY), to: nil
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
        try await expectPeriod(stats.period(at: 28), in: host)

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
        try await expectPeriod(stats.period(at: nil), in: host)
    }

    @Test("VoiceOver can inspect yesterday and today without changing the menu's height")
    func accessibleSelection() async throws {
        let stats = Self.stats
        let host = host(stats)
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformDecrement())
        try await expectPeriod(stats.period(at: 28), in: host)
        for _ in 0..<2 {
            #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformIncrement())
            try await expectPeriod(stats.period(at: 29), in: host)
        }
        #expect(host.hosting.fittingSize.height == GatewayActivityDashboardView.height(stats: stats))
    }

    private func host(
        _ stats: GatewayUsageStatsPresentation
    ) -> MenuControlTestHost<GatewayActivityDashboardView> {
        MenuControlTestHost(
            GatewayActivityDashboardView(runningCount: 3, waitingCount: 2, stats: stats),
            height: GatewayActivityDashboardView.height(stats: stats)
        )
    }

    private func expectPeriod(
        _ period: GatewayUsageStatsPresentation.Period,
        in host: MenuControlTestHost<GatewayActivityDashboardView>
    ) async throws {
        _ = try await eventually(description: "the inspected period and its six metrics") {
            try await MainActor.run {
                host.render()
                let chart = try host.element(label: L10n.string("Token history"))
                let values = try period.metrics.map {
                    try host.element(label: $0.title).accessibilityValueDescription()
                }
                return chart.accessibilityValueDescription() == period.accessibilityValue
                    && values == period.metrics.map(\.value) ? true : nil
            }
        }
    }

    private static var stats: GatewayUsageStatsPresentation {
        var yesterday = GatewayUsageDay(day: "2026-08-28")
        yesterday.requests = 100
        yesterday.failures = 10
        yesterday.webSearchCount = 2
        yesterday.usage = GatewayUsageTotals(inputTokens: 1_000_000, outputTokens: 10_000, cacheReadTokens: 200_000)
        var today = GatewayUsageDay(day: "2026-08-29")
        today.requests = 39
        today.failures = 10
        today.webSearchCount = 3
        today.usage = GatewayUsageTotals(inputTokens: 200_000, outputTokens: 6_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return GatewayUsageStatsPresentation(
            summary: GatewayUsageSummary(
                history: GatewayUsageHistory(days: [yesterday, today]),
                now: Date(timeIntervalSince1970: 1_788_000_000),
                calendar: calendar
            )
        )
    }
}
