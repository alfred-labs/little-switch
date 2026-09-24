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
        case chatGPT = "ChatGPT"
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
            case .chatGPT: "bubble.left.and.bubble.right"
            case .openCode: "terminal"
            }
        }
    }

    enum SidebarGroup: String, CaseIterable, Identifiable, Sendable {
        case common = "Common"
        case backends = "Backends"
        case apps = "Apps"

        var id: String { rawValue }

        var sections: [Section] {
            switch self {
            case .common: [.common]
            case .backends: [.providers, .webSearch, .monitoring]
            case .apps: [.claude, .codex, .chatGPT, .openCode]
            }
        }
    }

    enum ClaudePrimaryAction: Equatable, Sendable {
        case connect
        case apply
    }

    enum CodexPrimaryAction: Equatable, Sendable {
        case connect
        case apply
    }

    var configuration: AppConfiguration
    var desktopApplications: DesktopApplicationAvailability
    var launchingApplications: Set<DesktopApplication> = []
    var requestCount: Int
    var claudeRequestCount: Int
    var codexRequestCount: Int
    var proxyRunning: Bool
    var hasPendingCodexChanges: Bool
    var chatGPTStatus: ChatGPTConnectionStatus
    @ObservationIgnored private var chatGPTSnapshotSequence: UInt64
    var hasPendingClaudeMappings: Bool
    var hasPendingClaudeDesktopChanges: Bool
    @ObservationIgnored private var claudeDesktopSnapshotSequence: UInt64
    var claudeCodeStatus: ClaudeCodeConnectionStatus
    var hasPendingClaudeCodeChanges: Bool
    var claudeCodeMappedRouteIDs: [String]
    var openCodeStatus: OpenCodeConnectionStatus
    var hasPendingOpenCodeChanges: Bool
    /// Web search edits waiting to be applied. Held here rather than in the
    /// pane so leaving the section no longer throws typed settings away.
    var webSearchDraft: WebSearchPendingSettings?
    @ObservationIgnored private var webSearchDraftPublication: UUID?
    @ObservationIgnored private var webSearchDraftRevision: UInt64
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
    var imageInputState = ProviderImageInputState()
    private(set) var gatewayUsage: GatewayUsageSummary?
    /// Per-client consumption behind the menu's Claude and Codex tabs.
    private(set) var gatewayClientUsage: [GatewayClient: GatewayUsageSummary] = [:]
    var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    var isChangingLaunchAtLogin = false
    var errorMessage: String?

    init(snapshot: CoordinatorSnapshot = CoordinatorSnapshot(configuration: .init())) {
        configuration = snapshot.configuration
        desktopApplications = snapshot.desktopApplications
        requestCount = snapshot.requestCount
        claudeRequestCount = snapshot.claudeRequestCount
        codexRequestCount = snapshot.codexRequestCount
        proxyRunning = snapshot.proxyRunning
        hasPendingCodexChanges = snapshot.hasPendingCodexChanges
        chatGPTStatus = snapshot.chatGPTStatus
        chatGPTSnapshotSequence = snapshot.monitoringSnapshotSequence
        hasPendingClaudeMappings = snapshot.hasPendingClaudeMappings
        hasPendingClaudeDesktopChanges = snapshot.hasPendingClaudeDesktopChanges
        claudeDesktopSnapshotSequence = snapshot.monitoringSnapshotSequence
        claudeCodeStatus = snapshot.claudeCodeStatus
        hasPendingClaudeCodeChanges = snapshot.hasPendingClaudeCodeChanges
        claudeCodeMappedRouteIDs = snapshot.claudeCodeMappedRouteIDs
        openCodeStatus = snapshot.openCodeStatus
        hasPendingOpenCodeChanges = snapshot.hasPendingOpenCodeChanges
        webSearchDraft = snapshot.webSearchDraft
        webSearchDraftRevision = snapshot.webSearchDraftRevision
        monitoringDraft = snapshot.monitoringDraft
        monitoringStatus = snapshot.monitoringStatus
        monitoringApplying = snapshot.monitoringApplying
        monitoringNotice = snapshot.monitoringNotice
        monitoringTestResult = snapshot.monitoringTestResult
        monitoringHTTPSAvailable = snapshot.monitoringHTTPSAvailable
        monitoringSnapshotSequence = snapshot.monitoringSnapshotSequence
        credentialRefreshFailures = snapshot.credentialRefreshFailures
        lastScriptOutputs = snapshot.lastScriptOutputs
        imageInputState = ProviderImageInputState(snapshot: snapshot)
        responsesWireVerdicts = snapshot.responsesWireVerdicts
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
            L10n.string("Launch at login disabled")
        case .enabled:
            L10n.string("Launch at login enabled")
        case .requiresApproval:
            L10n.string("Approval required")
        case .unavailable:
            L10n.string("Launch at login unavailable")
        }
    }

    var launchAtLoginAccessibilityHint: String {
        switch launchAtLoginStatus {
        case .disabled:
            L10n.string("LittleSwitch does not open automatically")
        case .enabled:
            L10n.string("LittleSwitch opens in the menu bar when you log in")
        case .requiresApproval:
            L10n.string("Approve LittleSwitch in Login Items")
        case .unavailable:
            L10n.string("LittleSwitch is not registered with Login Items")
        }
    }

    var codexConnected: Bool {
        configuration.codex.connected
    }

    var codexPrimaryAction: CodexPrimaryAction {
        codexConnected ? .apply : .connect
    }

    var codexPrimaryActionTitle: String {
        L10n.string("Apply")
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
            return L10n.string("Choose an available approval review model before applying changes")
        }
        if codexExposedModelOptions.isEmpty {
            return codexConnected
                ? L10n.string("Expose at least one available model before applying changes")
                : L10n.string("Expose at least one available model before connecting Codex")
        }
        if isBusy {
            return L10n.string("An operation is in progress")
        }
        switch codexPrimaryAction {
        case .connect:
            return L10n.string("Connects Codex to LittleSwitch")
        case .apply:
            return hasPendingCodexChanges
                ? L10n.string("Applies pending settings")
                : L10n.string("No pending settings")
        }
    }

    var codexPrimaryActionAccessibilityValue: String {
        guard codexConnected else {
            return L10n.string("Codex disconnected")
        }
        return hasPendingCodexChanges ? L10n.string("Changes pending") : L10n.string("No pending changes")
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
        desktopApplications = snapshot.desktopApplications
        requestCount = snapshot.requestCount
        claudeRequestCount = snapshot.claudeRequestCount
        codexRequestCount = snapshot.codexRequestCount
        proxyRunning = snapshot.proxyRunning
        hasPendingCodexChanges = snapshot.hasPendingCodexChanges
        updateChatGPTStatus(snapshot.chatGPTStatus, snapshotSequence: snapshot.monitoringSnapshotSequence)
        hasPendingClaudeMappings = snapshot.hasPendingClaudeMappings
        updateClaudeDesktopPendingChanges(
            snapshot.hasPendingClaudeDesktopChanges,
            snapshotSequence: snapshot.monitoringSnapshotSequence
        )
        claudeCodeStatus = snapshot.claudeCodeStatus
        hasPendingClaudeCodeChanges = snapshot.hasPendingClaudeCodeChanges
        claudeCodeMappedRouteIDs = snapshot.claudeCodeMappedRouteIDs
        openCodeStatus = snapshot.openCodeStatus
        hasPendingOpenCodeChanges = snapshot.hasPendingOpenCodeChanges
        applyWebSearchDraft(snapshot)
        monitoringDraft = snapshot.monitoringDraft
        monitoringStatus = snapshot.monitoringStatus
        monitoringApplying = snapshot.monitoringApplying
        monitoringNotice = snapshot.monitoringNotice
        monitoringTestResult = snapshot.monitoringTestResult
        monitoringHTTPSAvailable = snapshot.monitoringHTTPSAvailable
        monitoringSnapshotSequence = snapshot.monitoringSnapshotSequence
        credentialRefreshFailures = snapshot.credentialRefreshFailures
        lastScriptOutputs = snapshot.lastScriptOutputs
        imageInputState = ProviderImageInputState(snapshot: snapshot)
        responsesWireVerdicts = snapshot.responsesWireVerdicts
        isBusy = false
        errorMessage = nil
    }

    /// Desktop catalog state shares the coordinator snapshot clock, but accepts
    /// polling updates independently of any in-progress monitoring action.
    func updateClaudeDesktopPendingChanges(_ pending: Bool, snapshotSequence: UInt64) {
        guard snapshotSequence >= claudeDesktopSnapshotSequence else { return }
        claudeDesktopSnapshotSequence = snapshotSequence
        setIfChanged(\.hasPendingClaudeDesktopChanges, to: pending)
    }

    /// Retain even a local clear until its own actor publication is acknowledged.
    func beginWebSearchDraftPublication(_ pending: WebSearchPendingSettings?) -> UUID {
        let publication = UUID()
        webSearchDraftPublication = publication
        webSearchDraft = pending
        return publication
    }

    func completeWebSearchDraftPublication(_ publication: UUID, snapshot: CoordinatorSnapshot) {
        guard webSearchDraftPublication == publication else { return }
        webSearchDraftPublication = nil
        applyWebSearchDraft(snapshot)
    }

    private func applyWebSearchDraft(_ snapshot: CoordinatorSnapshot) {
        guard webSearchDraftPublication == nil,
            snapshot.webSearchDraftRevision >= webSearchDraftRevision
        else { return }
        webSearchDraftRevision = snapshot.webSearchDraftRevision
        webSearchDraft = snapshot.webSearchDraft
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

}

extension AppModel {
    func updateChatGPTStatus(_ status: ChatGPTConnectionStatus, snapshotSequence: UInt64) {
        guard snapshotSequence >= chatGPTSnapshotSequence else { return }
        chatGPTSnapshotSequence = snapshotSequence
        setIfChanged(\.chatGPTStatus, to: status)
    }

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
