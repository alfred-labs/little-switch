import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch

public enum GatewayActivitySnapshot: Equatable, Sendable {
    case starting
    case running(ProviderRequestPoolSnapshot)
    case unavailable
}

/// Web search context for the menu dashboard: the engine name and today's
/// call count. The count itself is a grid metric; this row only feeds the
/// dashboard's accessibility value. Nil while search is disabled.
public struct GatewayWebSearchRow: Equatable, Sendable {
    public let engineName: String
    public let callCount: Int

    public init(engineName: String, callCount: Int) {
        self.engineName = engineName
        self.callCount = callCount
    }
}

public struct GatewayActivityPresentation: Equatable, Sendable {
    public struct Menu: Equatable, Sendable {
        public struct Dashboard: Equatable, Sendable {
            public let runningCount: Int
            public let waitingCount: Int
            public let stats: GatewayUsageStatsPresentation?
            public let webSearch: GatewayWebSearchRow?

            public init(
                runningCount: Int,
                waitingCount: Int,
                stats: GatewayUsageStatsPresentation?,
                webSearch: GatewayWebSearchRow? = nil
            ) {
                self.runningCount = runningCount
                self.waitingCount = waitingCount
                self.stats = stats
                self.webSearch = webSearch
            }
        }

        public let title: String
        public let symbolName: String
        public let accessibilityLabel: String
        public let accessibilityValue: String
        public let accessibilityHint: String
        public let dashboard: Dashboard?
    }

    public let menu: Menu

    public init(
        activity: GatewayActivitySnapshot,
        providers: [Provider],
        usage: GatewayUsageSummary? = nil,
        webSearchProvider: WebSearchProvider = .disabled
    ) {
        switch activity {
        case .starting:
            menu = Self.makeMenu(
                title: L10n.string("Starting gateway…"),
                symbolName: "hourglass",
                accessibilityValue: L10n.string("Starting gateway…")
            )
        case .unavailable:
            menu = Self.makeMenu(
                title: L10n.string("Gateway unavailable"),
                symbolName: "exclamationmark.triangle",
                accessibilityValue: L10n.string("Gateway unavailable")
            )
        case .running(let snapshot):
            let hasActivity = snapshot.totalRunning > 0 || snapshot.totalWaiting > 0
            let text =
                hasActivity
                ? L10n.string(
                    "\(snapshot.totalRunning) running · \(snapshot.totalWaiting) waiting"
                )
                : L10n.string("Gateway idle")
            menu = Self.runningMenu(
                snapshot: snapshot,
                providers: providers,
                title: text,
                usage: usage,
                webSearchProvider: webSearchProvider
            )
        }
    }

    static func makeMenu(
        title: String,
        symbolName: String,
        accessibilityValue: String,
        dashboard: Menu.Dashboard? = nil
    ) -> Menu {
        Menu(

            title: title,
            symbolName: symbolName,
            accessibilityLabel: L10n.string("Gateway activity"),
            accessibilityValue: accessibilityValue,
            accessibilityHint: L10n.string("Gateway requests and usage"),
            dashboard: dashboard
        )
    }
}
