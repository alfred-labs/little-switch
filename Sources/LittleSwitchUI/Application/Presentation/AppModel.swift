import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Observation

@MainActor
@Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case common = "General"
        case providers = "Providers"
        case webSearch = "Web Search"
        case monitoring = "Monitoring"
        case claude = "Claude"
        case codex = "Codex"
        case openCode = "OpenCode"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .common: "slider.horizontal.3"
            case .providers: "externaldrive.connected.to.line.below"
            case .webSearch: "globe"
            case .monitoring: "waveform.path.ecg"
            case .claude: "sparkles"
            case .codex: "chevron.left.forwardslash.chevron.right"
            case .openCode: "terminal"
            }
        }
    }

    enum SidebarGroup: String, CaseIterable, Identifiable, Sendable {
        case common = "Common"
        case backends = "Backends"
        case apps = "Apps"

        var id: String { rawValue }
        var title: String { rawValue }

        var sections: [Section] {
            switch self {
            case .common: [.common]
            case .backends: [.providers, .webSearch, .monitoring]
            case .apps: [.claude, .codex, .openCode]
            }
        }
    }

    enum ClaudePrimaryAction: Equatable, Sendable {
        case connect
    }

    enum CodexPrimaryAction: Equatable, Sendable {
        case connect
        case apply
    }

    var configuration: AppConfiguration
    var requestCount: Int
    var claudeRequestCount: Int
    var codexRequestCount: Int
    var proxyRunning: Bool
    var hasPendingCodexChanges: Bool
    var hasPendingClaudeMappings: Bool
    var claudeCodeStatus: ClaudeCodeConnectionStatus
    var hasPendingClaudeCodeChanges: Bool
    var claudeCodeMappedRouteIDs: [String]
    var openCodeStatus: OpenCodeConnectionStatus
    var hasPendingOpenCodeChanges: Bool
    /// Web search edits waiting to be applied. Held here rather than in the
    /// pane so leaving the section no longer throws typed settings away.
    var webSearchDraft: WebSearchInput?
    var monitoringDraft: MonitoringPendingSettings?
    var monitoringStatus: MonitoringExportStatus
    var monitoringApplying: Bool
    var monitoringNotice: String?
    var monitoringTestResult: MonitoringExportTestResult?
    var monitoringHTTPSAvailable: Bool
    var monitoringSnapshotSequence: UInt64
    var monitoringAction: MonitoringAction?
    var selectedSection: Section = .claude
    /// Presentation state retained while navigating between settings panes.
    var expandedCodexCatalogProviderIDs: Set<UUID> = []
    var isBusy = false
    private(set) var gatewayActivity: GatewayActivitySnapshot = .starting
    /// Learned Responses wire per provider: true = native `/v1/responses`,
    /// false = chat-completions adapter. Absent = not probed yet.
    private(set) var responsesWireVerdicts: [UUID: Bool] = [:]
    private(set) var credentialRefreshFailures: [UUID: String] = [:]
    private(set) var lastScriptOutputs: [UUID: String] = [:]
    private(set) var gatewayUsage: GatewayUsageSummary?
    /// Per-client consumption behind the menu's Claude and Codex tabs.
    private(set) var gatewayClientUsage: [GatewayClient: GatewayUsageSummary] = [:]
    var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    var isChangingLaunchAtLogin = false
    var errorMessage: String?

    init(snapshot: CoordinatorSnapshot = CoordinatorSnapshot(configuration: .init())) {
        configuration = snapshot.configuration
        requestCount = snapshot.requestCount
        claudeRequestCount = snapshot.claudeRequestCount
        codexRequestCount = snapshot.codexRequestCount
        proxyRunning = snapshot.proxyRunning
        hasPendingCodexChanges = snapshot.hasPendingCodexChanges
        hasPendingClaudeMappings = snapshot.hasPendingClaudeMappings
        claudeCodeStatus = snapshot.claudeCodeStatus
        hasPendingClaudeCodeChanges = snapshot.hasPendingClaudeCodeChanges
        claudeCodeMappedRouteIDs = snapshot.claudeCodeMappedRouteIDs
        openCodeStatus = snapshot.openCodeStatus
        hasPendingOpenCodeChanges = snapshot.hasPendingOpenCodeChanges
        webSearchDraft = snapshot.webSearchDraft
        monitoringDraft = snapshot.monitoringDraft
        monitoringStatus = snapshot.monitoringStatus
        monitoringApplying = snapshot.monitoringApplying
        monitoringNotice = snapshot.monitoringNotice
        monitoringTestResult = snapshot.monitoringTestResult
        monitoringHTTPSAvailable = snapshot.monitoringHTTPSAvailable
        monitoringSnapshotSequence = snapshot.monitoringSnapshotSequence
        credentialRefreshFailures = snapshot.credentialRefreshFailures
        lastScriptOutputs = snapshot.lastScriptOutputs
    }

    var providers: [Provider] {
        configuration.providers
    }

    var connected: Bool {
        configuration.connected
    }

    var autoMode: Bool {
        configuration.autoMode
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    var canChangeLaunchAtLogin: Bool {
        // Even `.unavailable` stays actionable: it maps SMAppService
        // `.notFound`, which macOS reports for never-registered apps, and
        // registration can still be attempted from there.
        !isChangingLaunchAtLogin
    }

    var launchAtLoginAccessibilityValue: String {
        switch launchAtLoginStatus {
        case .disabled:
            "Launch at login disabled"
        case .enabled:
            "Launch at login enabled"
        case .requiresApproval:
            "Approval required"
        case .unavailable:
            "Launch at login unavailable"
        }
    }

    var launchAtLoginAccessibilityHint: String {
        switch launchAtLoginStatus {
        case .disabled:
            "LittleSwitch does not open automatically"
        case .enabled:
            "LittleSwitch opens in the menu bar when you log in"
        case .requiresApproval:
            "Approve LittleSwitch in Login Items"
        case .unavailable:
            "LittleSwitch is not registered with Login Items"
        }
    }

    var codexConnected: Bool {
        configuration.codex.connected
    }

    var claudePrimaryAction: ClaudePrimaryAction? {
        // Routing remaps reach a connected Desktop live through the gateway,
        // so the only Desktop action left is connecting.
        connected ? nil : .connect
    }

    var claudePrimaryActionTitle: String {
        "Apply"
    }

    var canPerformClaudePrimaryAction: Bool {
        guard hasValidRouting, !isBusy else {
            return false
        }
        return claudePrimaryAction != nil
    }

    var claudePrimaryActionAccessibilityHint: String {
        if !hasValidRouting {
            return connected
                ? "Choose at least one available model to restore live routing"
                : "Assign at least one available model before applying settings"
        }
        if isBusy {
            return "An operation is in progress"
        }
        switch claudePrimaryAction {
        case .connect:
            return "Applies LittleSwitch settings to Claude Desktop"
        case nil:
            return "Model routing edits wait for Apply"
        }
    }

    var claudePrimaryActionAccessibilityValue: String {
        guard connected else {
            return "Claude disconnected"
        }
        return hasPendingClaudeMappings ? "Changes pending" : "No pending changes"
    }

    var codexPrimaryAction: CodexPrimaryAction {
        codexConnected ? .apply : .connect
    }

    var codexPrimaryActionTitle: String {
        "Apply"
    }

    var canPerformCodexPrimaryAction: Bool {
        guard !codexExposedModelOptions.isEmpty, !hasUnavailableCodexAutoReviewModel, !isBusy else {
            return false
        }
        switch codexPrimaryAction {
        case .connect:
            return true
        case .apply:
            return hasPendingCodexChanges
        }
    }

    var codexPrimaryActionAccessibilityHint: String {
        if hasUnavailableCodexAutoReviewModel {
            return "Choose an available approval review model before applying changes"
        }
        if codexExposedModelOptions.isEmpty {
            return codexConnected
                ? "Expose at least one available model before applying changes"
                : "Expose at least one available model before connecting Codex"
        }
        if isBusy {
            return "An operation is in progress"
        }
        switch codexPrimaryAction {
        case .connect:
            return "Connects Codex to LittleSwitch"
        case .apply:
            return hasPendingCodexChanges
                ? "Applies pending settings"
                : "No pending settings"
        }
    }

    var codexPrimaryActionAccessibilityValue: String {
        guard codexConnected else {
            return "Codex disconnected"
        }
        return hasPendingCodexChanges ? "Changes pending" : "No pending changes"
    }

    var claudeCustomModelCount: Int {
        let routeIDs = Set(ClaudeRoute.all.map(\.id))
        let availableMappings = Set(modelOptions.map(\.mapping))
        let mappedTargets = configuration.mappings.compactMap { routeID, mapping in
            routeIDs.contains(routeID) ? mapping : nil
        }
        return Set(mappedTargets).intersection(availableMappings).count
    }

    var codexCustomModelCount: Int {
        codexExposedModelOptions.count
    }

    var codexDefaultOptionID: String? {
        optionID(for: configuration.codex.defaultModel)
    }

    func isCodexModelExposed(_ mapping: ModelMapping) -> Bool {
        !configuration.codex.excludedModels.contains(mapping)
    }

    func apply(_ snapshot: CoordinatorSnapshot) {
        configuration = snapshot.configuration
        requestCount = snapshot.requestCount
        claudeRequestCount = snapshot.claudeRequestCount
        codexRequestCount = snapshot.codexRequestCount
        proxyRunning = snapshot.proxyRunning
        hasPendingCodexChanges = snapshot.hasPendingCodexChanges
        hasPendingClaudeMappings = snapshot.hasPendingClaudeMappings
        claudeCodeStatus = snapshot.claudeCodeStatus
        hasPendingClaudeCodeChanges = snapshot.hasPendingClaudeCodeChanges
        claudeCodeMappedRouteIDs = snapshot.claudeCodeMappedRouteIDs
        openCodeStatus = snapshot.openCodeStatus
        hasPendingOpenCodeChanges = snapshot.hasPendingOpenCodeChanges
        webSearchDraft = snapshot.webSearchDraft
        monitoringDraft = snapshot.monitoringDraft
        monitoringStatus = snapshot.monitoringStatus
        monitoringApplying = snapshot.monitoringApplying
        monitoringNotice = snapshot.monitoringNotice
        monitoringTestResult = snapshot.monitoringTestResult
        monitoringHTTPSAvailable = snapshot.monitoringHTTPSAvailable
        monitoringSnapshotSequence = snapshot.monitoringSnapshotSequence
        credentialRefreshFailures = snapshot.credentialRefreshFailures
        lastScriptOutputs = snapshot.lastScriptOutputs
        isBusy = false
        errorMessage = nil
    }

    func optionID(for routeID: String) -> String? {
        guard let mapping = configuration.mappings[routeID] else {
            return nil
        }
        return modelOptions.first { $0.mapping == mapping }?.id
    }

    func optionID(for mapping: ModelMapping?) -> String? {
        guard let mapping else {
            return nil
        }
        return modelOptions.first { $0.mapping == mapping }?.id
    }

    func mapping(for optionID: String?) -> ModelMapping? {
        guard let optionID else {
            return nil
        }
        return modelOptions.first { $0.id == optionID }?.mapping
    }

    private var hasValidRouting: Bool {
        RoutingSnapshot(
            generation: 0,
            providers: configuration.providers,
            mappings: configuration.mappings
        ).hasValidMapping
    }
}

extension AppModel {
    /// Assigns through the key path only when the value differs, so every
    /// gateway-state field shares one equality gate instead of each mutator
    /// hand-copying the guard (the publish storm the copies existed to
    /// prevent). Lives with the `private(set)` declarations it writes: the
    /// writable key paths only infer inside this file.
    private func setIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppModel, T>,
        to value: T
    ) {
        guard self[keyPath: keyPath] != value else {
            return
        }
        self[keyPath: keyPath] = value
    }

    func updateGatewayActivity(_ activity: GatewayActivitySnapshot) {
        setIfChanged(\.gatewayActivity, to: activity)
    }

    func updateResponsesWireVerdicts(_ verdicts: [UUID: Bool]) {
        setIfChanged(\.responsesWireVerdicts, to: verdicts)
    }

    func updateGatewayUsage(_ usage: GatewayUsageSummary?) {
        setIfChanged(\.gatewayUsage, to: usage)
    }

    func updateGatewayClientUsage(
        _ summaries: [GatewayClient: GatewayUsageSummary]?
    ) {
        setIfChanged(\.gatewayClientUsage, to: summaries ?? [:])
    }

    func updateCredentialRefreshFailures(_ failures: [UUID: String]) {
        setIfChanged(\.credentialRefreshFailures, to: failures)
    }

    func updateLastScriptOutputs(_ outputs: [UUID: String]) {
        setIfChanged(\.lastScriptOutputs, to: outputs)
    }
}
