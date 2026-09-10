import Foundation

public enum ProductIdentity {
    public static let displayName = "LittleSwitch"
    public static let bundleIdentifier = "com.alfredlabs.littleswitch"
    public static let applicationSupportDirectoryName = displayName
    public static let keychainService = bundleIdentifier
    public static let gatewayServerName = "LittleSwitch"
    public static let gatewayAPIKey = "little-switch"
    /// The loopback host every gateway surface binds and advertises; the
    /// TLS identity pins it in its SAN, so it is an invariant, not a knob.
    public static let gatewayLoopbackHost = "127.0.0.1"

    public static let gatewayHealthPath = "/health"
    /// Local observability surfaces never count or capture their own traffic.
    public static let gatewayMetricsPath = "/metrics"
    public static let gatewayLogsPath = "/logs"
    /// Prefix of the gateway's own API namespace (`/api/about`,
    /// `/api/web-search`), answered locally rather than routed to a
    /// provider. `/v1/` is vendor-contract territory — Anthropic and
    /// OpenAI only — and must never carry a gateway-native route.
    public static let gatewayAPIPathPrefix = "/api/"
    /// Compat alias prefix for clients still holding URLs written before
    /// the `/api/*` rename. A Desktop profile rewrites its URL at the next
    /// connect, so the aliases — and this constant with them — are removed
    /// in the release after the one that ships the new paths.
    public static let legacyGatewayInternalPathPrefix = "/_little_switch/"
    public static let logSubsystem = bundleIdentifier

    /// Whether the gateway answers this path locally rather than routing it
    /// to a provider: the root probes, the reserved metrics scrape, the
    /// `/api/` namespace, and the legacy aliases. Usage accounting skips
    /// these — the app's own probes are not traffic anyone routed, and
    /// counting them would inflate a quiet day with the app's own polling.
    public static func isInternalGatewayPath(_ path: String) -> Bool {
        path == gatewayHealthPath
            || path == gatewayMetricsPath
            || path == gatewayLogsPath
            || path.hasPrefix(gatewayAPIPathPrefix)
            || path.hasPrefix(legacyGatewayInternalPathPrefix)
    }

    /// The two shipped identities that predate the LittleSwitch name.
    /// Their on-disk artifacts migrate forward on first launch; nothing
    /// writes them anymore.
    public enum Legacy {
        /// The alfred-labs "Model Switch" era (2026).
        public enum ModelSwitch {
            public static let displayName = "Model Switch"
            public static let applicationSupportDirectoryName = displayName
            public static let keychainService = "com.alfredlabs.modelswitch"
            public static let gatewayAPIKey = "model-switch"
        }

        /// The original "Model Switcher" era.
        public enum ModelSwitcher {
            public static let displayName = "Model Switcher"
            public static let applicationSupportDirectoryName = displayName
            public static let keychainService = "com.modelswitcher.desktop"
            public static let gatewayAPIKey = "model-switcher"
        }
    }

    /// The application-support directory, migrating any directory left by a
    /// previous product identity forward under the current name.
    public static func applicationSupportRoot(
        in applicationSupport: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let canonical = applicationSupport.appending(
            path: applicationSupportDirectoryName,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: canonical.path) else {
            return canonical
        }
        for legacyName in [
            Legacy.ModelSwitch.applicationSupportDirectoryName,
            Legacy.ModelSwitcher.applicationSupportDirectoryName,
        ] {
            let legacy = applicationSupport.appending(
                path: legacyName,
                directoryHint: .isDirectory
            )
            if fileManager.fileExists(atPath: legacy.path) {
                try fileManager.moveItem(at: legacy, to: canonical)
                return canonical
            }
        }
        return canonical
    }
}
