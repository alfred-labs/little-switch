import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import Testing

@testable import LittleSwitchUI

@Suite("Gateway activity presentation")
struct GatewayActivityPresentationTests {
    private struct LifecycleCase {
        let activity: GatewayActivitySnapshot
        let title: String
        let symbolName: String
    }

    @Test("Activity envelope preserves every lifecycle state")
    func activityEnvelope() {
        let pool = poolSnapshot(running: 0, waiting: 0)

        #expect(GatewayActivitySnapshot.starting == .starting)
        #expect(GatewayActivitySnapshot.running(pool) == .running(pool))
        #expect(GatewayActivitySnapshot.unavailable == .unavailable)
    }

    @Test("Starting and unavailable menus remain truthful with or without configured providers")
    func lifecycleMenus() {
        let configurations = [
            [],
            [provider(id: alphaID, name: "Alpha", limit: 2), provider(id: betaID, name: "Beta", limit: 4)],
        ]
        let cases: [LifecycleCase] = [
            .init(activity: .starting, title: L10n.string("Starting gateway…"), symbolName: "hourglass"),
            .init(
                activity: .unavailable,
                title: L10n.string("Gateway unavailable"),
                symbolName: "exclamationmark.triangle"
            ),
        ]
        for providers in configurations {
            for scenario in cases {
                let presentation = GatewayActivityPresentation(activity: scenario.activity, providers: providers)
                #expect(
                    presentation.menu
                        == GatewayActivityPresentation.Menu(
                            title: scenario.title,
                            symbolName: scenario.symbolName,
                            accessibilityLabel: L10n.string("Gateway activity"),
                            accessibilityValue: scenario.title,
                            accessibilityHint: L10n.string("Gateway requests and usage"),
                            dashboard: nil
                        )
                )
            }
        }
    }

    @Test("No configured or draining providers produces the native empty state")
    func noProviders() {
        let idle = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 0, waiting: 0)),
            providers: []
        )

        #expect(idle.menu.title == L10n.string("Gateway idle"))
        #expect(idle.menu.symbolName == "checkmark.circle")
        #expect(idle.menu.accessibilityLabel == L10n.string("Gateway activity"))
        #expect(idle.menu.accessibilityValue == L10n.string("Gateway idle"))
        #expect(idle.menu.accessibilityHint == L10n.string("Gateway requests and usage"))
        #expect(idle.menu.dashboard == nil)
    }

    @Test("Idle configured providers retain a dashboard with zero activity")
    func idleConfiguredProviders() {
        let presentation = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 0, waiting: 0)),
            providers: [
                provider(id: betaID, name: "Beta", limit: 4),
                provider(id: alphaID, name: "Alpha", limit: 2),
            ]
        )

        #expect(
            presentation.menu
                == GatewayActivityPresentation.Menu(
                    title: L10n.string("Gateway idle"),
                    symbolName: "checkmark.circle",
                    accessibilityLabel: L10n.string("Gateway activity"),
                    accessibilityValue: L10n.string("Gateway idle"),
                    accessibilityHint: L10n.string("Gateway requests and usage"),
                    dashboard: .init(runningCount: 0, waitingCount: 0, stats: nil)
                )
        )
    }

    @Test("Search slots into the metrics grid and names the engine for accessibility")
    func webSearchRow() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        var history = GatewayUsageHistory()
        history.fold(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                webSearchCount: 7
            )
        )
        let usage = GatewayUsageSummary(history: history, now: now)

        let firecrawl = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 1, waiting: 0)),
            providers: [provider(id: alphaID, name: "Alpha", limit: 2)],
            usage: usage,
            webSearchProvider: .firecrawl
        )
        #expect(
            firecrawl.menu.dashboard?.webSearch
                == GatewayWebSearchRow(engineName: L10n.string("Firecrawl"), callCount: 7)
        )
        #expect(firecrawl.menu.dashboard?.stats?.period(at: nil).metrics.map(\.title) == statsMetricTitles)
        #expect(firecrawl.menu.dashboard?.stats?.period(at: nil).metrics[5].value == "7")

        for (engine, engineName) in [
            (WebSearchProvider.tavily, L10n.string("Tavily")),
            (.brave, L10n.string("Brave")),
            (.exa, L10n.string("Exa")),
        ] {
            let presentation = GatewayActivityPresentation(
                activity: .running(poolSnapshot(running: 1, waiting: 0)),
                providers: [provider(id: alphaID, name: "Alpha", limit: 2)],
                usage: usage,
                webSearchProvider: engine
            )
            #expect(
                presentation.menu.dashboard?.webSearch
                    == GatewayWebSearchRow(engineName: engineName, callCount: 7)
            )
        }

        let disabled = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 1, waiting: 0)),
            providers: [provider(id: alphaID, name: "Alpha", limit: 2)],
            usage: usage,
            webSearchProvider: .disabled
        )
        #expect(disabled.menu.dashboard?.webSearch == nil)
        #expect(disabled.menu.dashboard != nil)
        #expect(disabled.menu.dashboard?.stats?.period(at: nil).metrics.map(\.title) == statsMetricTitles)
        #expect(disabled.menu.dashboard?.stats?.period(at: nil).metrics[5].value == "7")

        // No usage history yet: the accessibility context still names the
        // engine, at zero, and no stats block exists to carry the metric.
        let noUsage = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 1, waiting: 0)),
            providers: [provider(id: alphaID, name: "Alpha", limit: 2)],
            usage: nil,
            webSearchProvider: .firecrawl
        )
        #expect(
            noUsage.menu.dashboard?.webSearch
                == GatewayWebSearchRow(engineName: L10n.string("Firecrawl"), callCount: 0)
        )
    }

    @Test("Singular activity and running-only activity remain semantic")
    func singularAndRunningActivity() {
        let waiting = providerSnapshot(
            id: alphaID,
            name: "Stale Alpha",
            limit: 31,
            running: 1,
            waiting: 1
        )
        let presentation = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 1, waiting: 1, providers: [waiting])),
            providers: [provider(id: alphaID, name: "Alpha", limit: 2)]
        )

        #expect(presentation.menu.dashboard == .init(runningCount: 1, waitingCount: 1, stats: nil))
        #expect(presentation.menu.title == L10n.string("\(1) running · \(1) waiting"))
        #expect(presentation.menu.symbolName == "hourglass")
        #expect(presentation.menu.accessibilityValue == L10n.string("\(1) running, \(1) waiting"))

        let runningOnly = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 1, waiting: 0)),
            providers: []
        )
        #expect(runningOnly.menu.title == L10n.string("\(1) running · \(0) waiting"))
        #expect(runningOnly.menu.symbolName == "bolt.horizontal.circle")
        #expect(runningOnly.menu.accessibilityValue == L10n.string("\(1) running, \(0) waiting"))
        #expect(runningOnly.menu.dashboard == nil)
    }

    @Test("Plural totals retain actual activity above the configured limit")
    func pluralActivity() {
        let live = providerSnapshot(
            id: alphaID,
            name: "Alpha",
            limit: 2,
            running: 5,
            waiting: 10
        )
        let presentation = GatewayActivityPresentation(
            activity: .running(poolSnapshot(running: 5, waiting: 10, providers: [live])),
            providers: [provider(id: alphaID, name: "Alpha", limit: 2)]
        )

        #expect(presentation.menu.dashboard == .init(runningCount: 5, waitingCount: 10, stats: nil))
        #expect(presentation.menu.title == L10n.string("\(5) running · \(10) waiting"))
        #expect(presentation.menu.symbolName == "hourglass")
        #expect(presentation.menu.accessibilityLabel == L10n.string("Gateway activity"))
        #expect(presentation.menu.accessibilityValue == L10n.string("\(5) running, \(10) waiting"))
        #expect(presentation.menu.accessibilityHint == L10n.string("Gateway requests and usage"))
    }

}

private let alphaID = UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
private let betaID = UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
private let statsMetricTitles = [
    L10n.string("Input tokens"), L10n.string("Cached tokens"), L10n.string("Output tokens"),
    L10n.string("Requests"), L10n.string("Errors"), L10n.string("Web searches"),
]

private func provider(id: UUID, name: String, limit: Int) -> Provider {
    Provider(
        id: id,
        name: name,
        baseURL: "https://example.com",
        authMode: .none,
        maximumParallelRequests: limit
    )
}

private func providerSnapshot(
    id: UUID,
    name: String,
    limit: Int,
    running: Int,
    waiting: Int
) -> ProviderRequestPoolProviderSnapshot {
    ProviderRequestPoolProviderSnapshot(
        id: id,
        displayName: name,
        maximumParallelRequests: limit,
        runningCount: running,
        waitingCount: waiting,
        retainedWaitingBytes: 0,
        oldestWaitDuration: nil,
        isRemoved: false
    )
}

private func poolSnapshot(
    running: Int,
    waiting: Int,
    providers: [ProviderRequestPoolProviderSnapshot] = []
) -> ProviderRequestPoolSnapshot {
    ProviderRequestPoolSnapshot(
        totalRunning: running,
        totalWaiting: waiting,
        providers: providers
    )
}
