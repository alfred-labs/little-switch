import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

/// The dashboard is hosted in a fixed-frame `NSHostingView`, so its declared
/// height has to equal what SwiftUI actually lays out. Anything less clips the
/// bottom of the menu block silently.
@MainActor
@Suite("Gateway dashboard height", .appKitIsolation)
struct GatewayActivityDashboardHeightTests {
    @Test("The declared height matches the laid-out height in every composition")
    func declaredHeightMatchesLayout() {
        let stats = GatewayUsageStatsPresentation(summary: busySummary())
        let webSearch = GatewayWebSearchRow(engineName: L10n.string("Firecrawl"), callCount: 12)

        for statsValue in [nil, stats] {
            expectMatchingHeight(stats: statsValue, webSearch: webSearch)
        }
    }

    @Test("The chart keeps the history caption until a day is inspected")
    func restingSelectionIsEmpty() async throws {
        let stats = GatewayUsageStatsPresentation(summary: busySummary())
        let view = GatewayActivityDashboardView(
            runningCount: 3,
            waitingCount: 1,
            stats: stats
        )
        let host = MenuControlTestHost(view, height: GatewayActivityDashboardView.height(stats: stats))
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                == stats.period(at: nil).accessibilityValue
        )
        #expect(try host.element(label: L10n.string("Requests")).accessibilityValueDescription() == "30")
        #expect(!host.textContent.contains("Top model"))
        #expect(!host.textContent.contains("Details"))
    }

    private func expectMatchingHeight(
        stats: GatewayUsageStatsPresentation?,
        webSearch: GatewayWebSearchRow? = nil
    ) {
        let view = GatewayActivityDashboardView(
            runningCount: 3,
            waitingCount: 1,
            stats: stats,
            webSearch: webSearch
        )
        let declared = GatewayActivityDashboardView.height(stats: stats)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: StatusMenuLayout.width, height: declared)
        hosting.layoutSubtreeIfNeeded()

        #expect(declared == hosting.fittingSize.height)
    }

    private func busySummary() -> GatewayUsageSummary {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        var history = GatewayUsageHistory()
        for offset in 0..<GatewayUsageSummary.seriesDays {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: now) else {
                continue
            }
            history.fold(
                GatewayUsageEvent(
                    finishedAt: day,
                    outcome: .succeeded,
                    client: .claude,
                    routeID: "claude-opus-5",
                    providerName: "z.ai",
                    modelID: "glm-4.7",
                    durationMilliseconds: 900,
                    usage: GatewayUsageTotals(inputTokens: 1_000, outputTokens: 200)
                )
            )
        }
        return GatewayUsageSummary(history: history, now: now)
    }
}
