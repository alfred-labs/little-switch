import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch

/// Running-state projection for the gateway activity menu dashboard.
extension GatewayActivityPresentation {
    static func runningMenu(
        snapshot: ProviderRequestPoolSnapshot,
        providers: [Provider],
        title: String,
        usage: GatewayUsageSummary?,
        webSearchProvider: WebSearchProvider
    ) -> Menu {
        let stats = usage.map { GatewayUsageStatsPresentation(summary: $0) }
        let symbolName: String
        if snapshot.totalWaiting > 0 {
            symbolName = "hourglass"
        } else if snapshot.totalRunning > 0 {
            symbolName = "bolt.horizontal.circle"
        } else {
            symbolName = "checkmark.circle"
        }
        let accessibilityValue =
            snapshot.totalRunning == 0 && snapshot.totalWaiting == 0
            ? "Gateway idle"
            : "\(snapshot.totalRunning) running, \(snapshot.totalWaiting) waiting"
        let dashboard: Menu.Dashboard?
        if !providers.isEmpty || snapshot.providers.contains(where: \.isRemoved) {
            dashboard = Menu.Dashboard(
                runningCount: snapshot.totalRunning,
                waitingCount: snapshot.totalWaiting,
                stats: stats,
                webSearch: Self.webSearchRow(
                    provider: webSearchProvider,
                    usage: usage
                )
            )
        } else {
            dashboard = nil
        }
        return Self.makeMenu(
            title: title,
            symbolName: symbolName,
            accessibilityValue: accessibilityValue,
            dashboard: dashboard
        )
    }

    /// Nil while search is disabled. The menu has no dedicated search row:
    /// the call count lives in the metrics grid, so this only feeds the
    /// dashboard's accessibility value.
    static func webSearchRow(
        provider: WebSearchProvider,
        usage: GatewayUsageSummary?
    ) -> GatewayWebSearchRow? {
        guard provider != .disabled else {
            return nil
        }
        return GatewayWebSearchRow(
            engineName: engineName(provider),
            callCount: usage?.today.webSearchCount ?? 0
        )
    }

    private static func engineName(_ provider: WebSearchProvider) -> String {
        switch provider {
        case .firecrawl: "Firecrawl"
        case .tavily: "Tavily"
        case .brave: "Brave"
        case .exa: "Exa"
        case .disabled: "Off"
        }
    }
}
