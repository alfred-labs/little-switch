import Testing

@testable import RepositoryTooling

@Suite("Repository production coverage scope")
struct CoverageRepositoryScopeTests {
    @Test("Every production source is measured or listed in the reviewed adapter exclusions")
    func reviewedExclusions() throws {
        let scope = try CoverageScope.load(root: RepositoryFixture.root())
        let excluded = scope.excluded.map(\.path)
        #expect(excluded == Self.reviewedExclusions.sorted())
        #expect(scope.all == scope.all.sorted())
        #expect(scope.measured == scope.measured.sorted())
        #expect(excluded == excluded.sorted())
        #expect(scope.measured.count + scope.excluded.count == scope.all.count)
        #expect((scope.measured + excluded).sorted() == scope.all)
        #expect(scope.measured.contains("Sources/LittleSwitchUI/MenuBar/StatusMenuSwitchTrack.swift"))
        #expect(scope.measured.allSatisfy { $0.hasPrefix("Sources/") })
        #expect(scope.excluded.allSatisfy { !$0.rationale.isEmpty })
        let transport = try #require(scope.excluded.first { $0.path.hasSuffix("/AsyncHTTPTransport.swift") })
        #expect(transport.rationale.contains("AsyncHTTPClient"))
        #expect(transport.rationale.contains("NIO"))
        #expect(!transport.rationale.contains("URLSession"))
    }

    // Explicit inventory preserves the existing reviewed exclusions. Domain moves
    // update paths; any additional exclusion still requires a named justification.
    private static let reviewedExclusions = [
        // Common/domain splits verified absent from the full llvm-cov raw report.
        "Sources/LittleSwitchCommon/Domain/Clients/GatewayClient.swift",
        "Sources/LittleSwitchCommon/Domain/Traffic/TrafficAction.swift",
        "Sources/LittleSwitchCore/Monitoring/Export/OTLP/OTLPHTTPResponse.swift",
        "Sources/LittleSwitchCore/Protocols/Anthropic/AnthropicModelTurn.swift",
        "Sources/LittleSwitchCore/Protocols/Anthropic/Search/WebSearchToolCall.swift",
        "Sources/LittleSwitchCore/Protocols/OpenAI/Compaction/ResponsesCompactionResult.swift",
        "Sources/LittleSwitchCore/Protocols/OpenAI/ResponsesModelTurn.swift",
        "Sources/LittleSwitchCore/Protocols/OpenAI/Streaming/ChatCompletionUsage.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/AppliedCodexSnapshot.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/AppliedCodexState.swift",
        "Sources/LittleSwitch/main.swift",
        "Sources/LittleSwitchCore/Security/Keychain/KeychainSecretStore.swift",
        "Sources/LittleSwitchCore/Security/TLS/GatewayTLSTrust.swift",
        "Sources/LittleSwitchTransport/HTTP/AsyncHTTPTransport.swift",
        "Sources/LittleSwitchUI/Application/Lifecycle/LittleSwitchApplicationDelegate.swift",
        "Sources/LittleSwitchUI/Application/Presentation/LittleSwitchApplicationDelegateConnections.swift",
        "Sources/LittleSwitchUI/Application/Presentation/LittleSwitchApplicationDelegatePresentation.swift",
        "Sources/LittleSwitchUI/Settings/Root/SettingsChrome.swift",
        "Sources/LittleSwitchUI/Settings/Root/SettingsSplitView.swift",
        "Sources/LittleSwitchUI/Settings/Root/SettingsView.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/ClaudeCodeIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/ClaudeIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/OllamaIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/OpenCodeIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/ZaiIcon.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsCard.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsConnectionStatus.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsDisclosureGroupStyle.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsLayout.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsMappingRow.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsPage.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsSection.swift",
        "Sources/LittleSwitchUI/Settings/Shared/SettingsToolbar.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayActivityDashboardView.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayOverviewChartView.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayOverviewLayout.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayQueueSummaryView.swift",
        "Sources/LittleSwitchUI/Features/Activity/LittleSwitchApplicationDelegateGatewayActivity.swift",
        "Sources/LittleSwitchUI/Features/Activity/Traffic/OSLogTrafficLogger.swift",
        "Sources/LittleSwitchUI/Features/Clients/Claude/ClaudeApplicationController.swift",
        "Sources/LittleSwitchUI/Settings/Clients/Claude/ClaudeSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Clients/Claude/LittleSwitchApplicationDelegateClaudeProducts.swift",
        "Sources/LittleSwitchUI/Settings/Clients/ClaudeCode/ClaudeCodeSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/CodexApplicationController.swift",
        "Sources/LittleSwitchUI/Settings/Clients/Codex/CodexSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/LittleSwitchApplicationDelegateCodexProducts.swift",
        "Sources/LittleSwitchUI/Settings/Clients/Codex/ModelCatalogHeader.swift",
        "Sources/LittleSwitchUI/Settings/Clients/Codex/ModelCatalogView.swift",
        "Sources/LittleSwitchUI/Features/Clients/OpenCode/LittleSwitchApplicationDelegateOpenCode.swift",
        "Sources/LittleSwitchUI/Settings/Clients/OpenCode/OpenCodeSettingsView.swift",
        "Sources/LittleSwitchUI/Settings/General/CommonSettingsView.swift",
        "Sources/LittleSwitchUI/Features/General/LittleSwitchApplicationDelegateGatewaySettings.swift",
        "Sources/LittleSwitchUI/Features/General/LittleSwitchApplicationDelegateLaunchAtLogin.swift",
        "Sources/LittleSwitchUI/Features/Monitoring/LittleSwitchApplicationDelegateMonitoring.swift",
        "Sources/LittleSwitchUI/Settings/Monitoring/MonitoringDestinationFields.swift",
        "Sources/LittleSwitchUI/Settings/Monitoring/MonitoringExportStatusView.swift",
        "Sources/LittleSwitchUI/Settings/Monitoring/MonitoringLocalEndpointsView.swift",
        "Sources/LittleSwitchUI/Settings/Monitoring/MonitoringSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Providers/LittleSwitchApplicationDelegateProviderTest.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderEditor.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderEditorAdvanced.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderEditorCompatibility.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderEditorConnectionDetails.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderEditorCredentials.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderEditorNotice.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderModelContextTable.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderSettingsRow.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProvidersSettingsView.swift",
        "Sources/LittleSwitchUI/Settings/Search/WebSearchSettingsView.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuClaudeTabView.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuCodexReviewModelRow.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuCodexTabView.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuSettingsSectionHeader.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuStatsBlockLayout.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuStatusView.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuTabSwitcherView.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuTokenHistoryChart.swift",
        "Sources/LittleSwitchUI/MenuBar/MenuUsageStatsBlock.swift",
        "Sources/LittleSwitchUI/MenuBar/StatusItemVisibilityRecovery.swift",
        "Sources/LittleSwitchUI/MenuBar/StatusMenuLayout.swift",
        "Sources/LittleSwitchUI/MenuBar/StatusMenuSwitchStyle.swift",
        "Sources/LittleSwitchUI/Platform/LoginItems/ServiceManagementLaunchAtLoginService.swift",
        "Sources/LittleSwitchUI/Platform/ProcessHandoff/ApplicationHandoffSystem.swift",
        "Sources/LittleSwitchUI/Platform/Updates/DeveloperIDSignatureProbe.swift",
        "Sources/LittleSwitchUI/Platform/Updates/SoftwareUpdateProviding.swift",
        "Sources/LittleSwitchUI/Platform/Updates/SparkleSoftwareUpdateController.swift",
        // Domain extractions verified against llvm-cov: declarations emit no regions.
        "Sources/LittleSwitchCommon/Domain/Providers/Capabilities/ProviderDisabledThinkingOverride.swift",
        "Sources/LittleSwitchCommon/Domain/Providers/Capabilities/ProviderImageInputOverride.swift",
        "Sources/LittleSwitchCommon/Domain/Providers/Capabilities/ProviderResponsesWireOverride.swift",
        "Sources/LittleSwitchCore/Providers/Capabilities/ProviderWireProbing.swift",
        "Sources/LittleSwitchCommon/Domain/Providers/Credentials/CredentialSource.swift",
        "Sources/LittleSwitchCommon/Domain/Providers/Models/ProviderStatus.swift",
        "Sources/LittleSwitchSearch/Contracts/WebSearchProviderError.swift",
        "Sources/LittleSwitchSearch/Contracts/WebSearchSearching.swift",
        "Sources/LittleSwitchUI/Application/Coordination/GatewayServing.swift",
        "Sources/LittleSwitchUI/Features/Clients/ClaudeCode/ClaudeCodeConnectionStatus.swift",
        "Sources/LittleSwitchUI/Features/Clients/OpenCode/OpenCodeConnectionStatus.swift",
        "Sources/LittleSwitchUI/Settings/Providers/ProviderTestOutcome.swift",
    ]
}
