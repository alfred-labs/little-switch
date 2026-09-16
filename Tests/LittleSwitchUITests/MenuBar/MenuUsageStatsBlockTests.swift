import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Client menu token history")
struct MenuUsageStatsBlockTests {
    @Test("The client block exposes the six Overview insights")
    func sixInsights() async throws {
        let stats = Self.stats
        let metrics = stats.period(at: nil).metrics
        #expect(
            metrics.map(\.title)
                == [
                    L10n.string("Input tokens (est.)"), L10n.string("Cached tokens"), L10n.string("Output tokens"),
                    L10n.string("Requests"), L10n.string("Errors"), L10n.string("Web searches"),
                ]
        )
        let host = MenuControlTestHost(MenuUsageStatsBlock(stats: stats), height: MenuUsageStatsBlock.fixedHeight)
        defer { host.close() }
        try await host.activateAccessibility()
        let accessibleValues = try metrics.map {
            try host.element(label: $0.title).accessibilityValueDescription()
        }
        #expect(accessibleValues == metrics.map(\.accessibilityValue))
    }

    @Test("The client history opens with its complete thirty-day total and the Overview chart height")
    func aggregateHistory() async throws {
        let stats = Self.stats
        let host = MenuControlTestHost(MenuUsageStatsBlock(stats: stats), height: MenuUsageStatsBlock.fixedHeight)
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(
            try host.element(label: L10n.string("Token history")).accessibilityValueDescription()
                == accessibility(
                    label: L10n.string("\(30) days"),
                    tokens: 1_650_000,
                    estimated: true
                )
        )
        #expect(
            MenuUsageStatsBlock.fixedHeight
                == GatewayOverviewLayout.chartHeight + GatewayOverviewLayout.sectionSpacing
                + MenuStatsBlockLayout.metricsHeight
        )
        #expect(host.hosting.fittingSize.height == MenuUsageStatsBlock.fixedHeight)
        #expect(try host.nativeView(of: MouseLocationReader.TrackingView.self).bounds.height == 92)
    }

    @Test("Pointer inspection changes the client token headline and all six insights together")
    func pointerSelection() async throws {
        let stats = Self.stats
        let host = MenuControlTestHost(MenuUsageStatsBlock(stats: stats), height: MenuUsageStatsBlock.fixedHeight)
        defer { host.close() }
        try await host.activateAccessibility()
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

    @Test("VoiceOver can inspect a day and restore all thirty days without changing the block height")
    func accessibleSelection() async throws {
        let stats = Self.stats
        let host = MenuControlTestHost(MenuUsageStatsBlock(stats: stats), height: MenuUsageStatsBlock.fixedHeight)
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformDecrement())
        try await expectPeriod(stats.period(at: 28), in: host)
        for _ in 0..<2 {
            #expect(try host.element(label: L10n.string("Token history")).accessibilityPerformIncrement())
            try await expectPeriod(stats.period(at: 29), in: host)
        }
        let actions = try #require(
            try host.element(label: L10n.string("Token history")).object.accessibilityCustomActions?())
        let reset = try #require(actions.first { $0.name == L10n.string("Show 30 days") })
        let performReset = try #require(reset.handler)
        #expect(performReset())
        try await expectPeriod(stats.period(at: nil), in: host)
        #expect(host.hosting.fittingSize.height == MenuUsageStatsBlock.fixedHeight)
    }

    @Test("Unknown historical counts have readable accessible values without changing layout")
    func unavailableCounts() async throws {
        var day = GatewayUsageDay(day: "2026-08-29")
        day.requests = 4
        day.failures = 1
        day.webSearchCount = 2
        day.clients = ["claude": 2, "codex": 2]
        let host = MenuControlTestHost(
            MenuUsageStatsBlock(stats: Self.presentation(days: [day])),
            height: MenuUsageStatsBlock.fixedHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()
        for label in [L10n.string("Errors"), L10n.string("Web searches")] {
            #expect(
                try host.element(label: label).accessibilityValueDescription()
                    == L10n.string("Unavailable for this period"))
        }
        #expect(host.hosting.fittingSize.height == MenuUsageStatsBlock.fixedHeight)
    }

    private func expectPeriod(
        _ period: GatewayUsageStatsPresentation.Period,
        in host: MenuControlTestHost<MenuUsageStatsBlock>
    ) async throws {
        _ = try await eventually(description: "the client token period and six insights") {
            try await MainActor.run {
                host.render()
                let chart = try host.element(label: L10n.string("Token history"))
                let values = try period.metrics.map {
                    try host.element(label: $0.title).accessibilityValueDescription()
                }
                return chart.accessibilityValueDescription() == period.accessibilityValue
                    && values == period.metrics.map(\.accessibilityValue) ? true : nil
            }
        }
    }

    private static var stats: GatewayUsageStatsPresentation {
        var earlier = GatewayUsageDay(day: "2026-08-05")
        earlier.clients = ["claude": 10]
        earlier.clientUsage = ["claude": GatewayClientUsage(estimatedTokens: 1_000_000)]
        var yesterday = GatewayUsageDay(day: "2026-08-28")
        yesterday.clients = ["claude": 4]
        yesterday.clientUsage = ["claude": GatewayClientUsage(estimatedTokens: 600_000)]
        var today = GatewayUsageDay(day: "2026-08-29")
        today.clients = ["claude": 2, "codex": 100]
        today.clientUsage = [
            "claude": GatewayClientUsage(estimatedTokens: 50_000),
            "codex": GatewayClientUsage(estimatedTokens: 100_000_000),
        ]
        return presentation(days: [earlier, yesterday, today])
    }

    private static func presentation(days: [GatewayUsageDay]) -> GatewayUsageStatsPresentation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return GatewayUsageStatsPresentation(
            summary: GatewayUsageSummary(
                history: GatewayUsageHistory(days: days),
                client: .claude,
                now: Date(timeIntervalSince1970: 1_788_000_000),
                calendar: calendar
            )
        )
    }
}

private func accessibility(label: String, tokens: Int, estimated: Bool = false) -> String {
    let localizedTotal = L10n.string(
        "\(label), \(GatewayUsageFormat.count(tokens)) tokens"
    )
    return estimated
        ? L10n.string("\(localizedTotal), includes estimates")
        : localizedTotal
}
