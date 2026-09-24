import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    public func snapshot() async -> CoordinatorSnapshot {
        let desktopAvailability = await desktopApplications?.availability() ?? .init()
        _ = await responsesWireVerdicts()
        reconcileCodexDraft()
        reconcileOpenCodeDraft()
        // The mapping draft reconciles first: the Claude Code draft below
        // reconciles against the mappings it merges in.
        reconcileClaudeMappingsDraft()
        reconcileClaudeCodeDraft()
        let count = await gatewayState?.sessionRequestCount ?? 0
        let claudeCount = await gatewayState?.claudeSessionRequestCount ?? 0
        let codexCount = await gatewayState?.codexSessionRequestCount ?? 0
        let proxyRunning = await gatewayServer?.isRunning ?? false
        let refreshFailures = await credentialRefresher.failureMessages()
        let scriptOutputs = await credentialRefresher.lastScriptOutputs()
        let monitoringStatus = await monitoringStatusSnapshot()
        monitoringSnapshotSequence &+= 1
        var effectiveConfiguration = configuration
        if let pendingClaudeMappings {
            effectiveConfiguration.mappings = pendingClaudeMappings
        }
        effectiveConfiguration =
            pendingCodexSettings?.applying(to: effectiveConfiguration)
            ?? effectiveConfiguration
        effectiveConfiguration =
            pendingClaudeCodeSettings?.applying(to: effectiveConfiguration)
            ?? effectiveConfiguration
        if effectiveConfiguration.openCode.connected || pendingOpenCodeSettings != nil {
            effectiveConfiguration.openCode = effectiveConfiguration.openCode.normalized(
                providers: effectiveConfiguration.providers,
                codex: effectiveConfiguration.codex
            )
        }
        effectiveConfiguration =
            pendingOpenCodeSettings?.applying(to: effectiveConfiguration)
            ?? effectiveConfiguration
        var result = CoordinatorSnapshot(
            configuration: effectiveConfiguration,
            desktopApplications: desktopAvailability,
            requestCount: count,
            claudeRequestCount: claudeCount,
            codexRequestCount: codexCount,
            proxyRunning: proxyRunning,
            hasPendingCodexChanges: hasPendingCodexChanges,
            hasPendingClaudeMappings: hasPendingClaudeMappings,
            hasPendingClaudeDesktopChanges: hasPendingClaudeDesktopChanges,
            claudeCodeStatus: claudeCodeStatus,
            hasPendingClaudeCodeChanges: hasPendingClaudeCodeChanges,
            // The route list follows the same effective view as the
            // mappings above: the Claude Code pane drafts with the pending
            // remaps, not against the applied set they will replace.
            claudeCodeMappedRouteIDs: effectiveConfiguration.claudeCode.mappedRouteIDs(
                providers: effectiveConfiguration.providers,
                mappings: effectiveConfiguration.mappings
            ),
            openCodeStatus: openCodeStatus,
            hasPendingOpenCodeChanges: hasPendingOpenCodeChanges,
            webSearchDraft: pendingWebSearchSettings,
            webSearchDraftRevision: webSearchDraftRevision,
            monitoringDraft: pendingMonitoringSettings,
            monitoringStatus: monitoringStatus,
            monitoringApplying: monitoringApplyInProgress,
            monitoringNotice: monitoringNotice,
            monitoringTestResult: monitoringTestResult,
            monitoringHTTPSAvailable: proxyRunning && gatewayHasTLSIdentity
                && tlsProvisioner?.isTrusted(secretStore: secretStore) == true,
            monitoringSnapshotSequence: monitoringSnapshotSequence,
            credentialRefreshFailures: refreshFailures,
            lastScriptOutputs: scriptOutputs,
            imageProbeProgress: imageProbeProgress
        )
        result.imageInputDiagnostics = imageInputDiagnostics
        result.imageInputPersistenceFailures = imageInputPersistenceFailures
        result.responsesWireVerdicts = catalogResponsesWireVerdicts
        await reconcileChatGPTConnection()
        result.chatGPTStatus = chatGPTStatus
        return result
    }
}
