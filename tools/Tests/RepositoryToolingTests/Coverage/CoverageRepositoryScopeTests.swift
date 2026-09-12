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
        "Sources/LittleSwitch/main.swift",
        "Sources/LittleSwitchCore/Security/Keychain/KeychainSecretStore.swift",
        "Sources/LittleSwitchCore/Security/TLS/GatewayTLSTrust.swift",
        "Sources/LittleSwitchTransport/HTTP/AsyncHTTPTransport.swift",
        "Sources/LittleSwitchUI/Application/Lifecycle/LittleSwitchApplicationDelegate.swift",
        "Sources/LittleSwitchUI/Application/Presentation/LittleSwitchApplicationDelegateConnections.swift",
        "Sources/LittleSwitchUI/Application/Presentation/LittleSwitchApplicationDelegatePresentation.swift",
        "Sources/LittleSwitchUI/Application/Settings/SettingsChrome.swift",
        "Sources/LittleSwitchUI/Application/Settings/SettingsSplitView.swift",
        "Sources/LittleSwitchUI/Application/Settings/SettingsView.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/ClaudeCodeIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/ClaudeIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/OllamaIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/OpenCodeIcon.swift",
        "Sources/LittleSwitchUI/Components/BrandIcons/ZaiIcon.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsCard.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsConnectionStatus.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsDisclosureGroupStyle.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsLayout.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsMappingRow.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsPage.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsSection.swift",
        "Sources/LittleSwitchUI/Components/Settings/SettingsToolbar.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayActivityDashboardView.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayOverviewChartView.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayOverviewLayout.swift",
        "Sources/LittleSwitchUI/Features/Activity/GatewayQueueSummaryView.swift",
        "Sources/LittleSwitchUI/Features/Activity/LittleSwitchApplicationDelegateGatewayActivity.swift",
        "Sources/LittleSwitchUI/Features/Activity/Traffic/OSLogTrafficLogger.swift",
        "Sources/LittleSwitchUI/Features/Clients/Claude/ClaudeApplicationController.swift",
        "Sources/LittleSwitchUI/Features/Clients/Claude/ClaudeSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Clients/Claude/LittleSwitchApplicationDelegateClaudeProducts.swift",
        "Sources/LittleSwitchUI/Features/Clients/ClaudeCode/ClaudeCodeSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/CodexApplicationController.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/CodexSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/LittleSwitchApplicationDelegateCodexProducts.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/ModelCatalogHeader.swift",
        "Sources/LittleSwitchUI/Features/Clients/Codex/ModelCatalogView.swift",
        "Sources/LittleSwitchUI/Features/Clients/OpenCode/LittleSwitchApplicationDelegateOpenCode.swift",
        "Sources/LittleSwitchUI/Features/Clients/OpenCode/OpenCodeSettingsView.swift",
        "Sources/LittleSwitchUI/Features/General/CommonSettingsView.swift",
        "Sources/LittleSwitchUI/Features/General/LittleSwitchApplicationDelegateGatewaySettings.swift",
        "Sources/LittleSwitchUI/Features/General/LittleSwitchApplicationDelegateLaunchAtLogin.swift",
        "Sources/LittleSwitchUI/Features/Monitoring/LittleSwitchApplicationDelegateMonitoring.swift",
        "Sources/LittleSwitchUI/Features/Monitoring/MonitoringDestinationFields.swift",
        "Sources/LittleSwitchUI/Features/Monitoring/MonitoringExportStatusView.swift",
        "Sources/LittleSwitchUI/Features/Monitoring/MonitoringLocalEndpointsView.swift",
        "Sources/LittleSwitchUI/Features/Monitoring/MonitoringSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Providers/LittleSwitchApplicationDelegateProviderTest.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderEditor.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderEditorAdvanced.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderEditorCompatibility.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderEditorConnectionDetails.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderEditorCredentials.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderEditorNotice.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderModelContextTable.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderSettingsRow.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProvidersSettingsView.swift",
        "Sources/LittleSwitchUI/Features/Search/WebSearchSettingsView.swift",
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
        "Sources/LittleSwitchCore/Providers/Capabilities/ProviderDisabledThinkingOverride.swift",
        "Sources/LittleSwitchCore/Providers/Capabilities/ProviderImageInputOverride.swift",
        "Sources/LittleSwitchCore/Providers/Capabilities/ProviderResponsesWireOverride.swift",
        "Sources/LittleSwitchCore/Providers/Capabilities/ProviderWireProbing.swift",
        "Sources/LittleSwitchCore/Providers/Models/CredentialSource.swift",
        "Sources/LittleSwitchCore/Providers/Models/ProviderStatus.swift",
        "Sources/LittleSwitchSearch/Contracts/WebSearchProviderError.swift",
        "Sources/LittleSwitchSearch/Contracts/WebSearchSearching.swift",
        "Sources/LittleSwitchUI/Application/Coordination/GatewayServing.swift",
        "Sources/LittleSwitchUI/Features/Clients/ClaudeCode/ClaudeCodeConnectionStatus.swift",
        "Sources/LittleSwitchUI/Features/Clients/OpenCode/OpenCodeConnectionStatus.swift",
        "Sources/LittleSwitchUI/Features/Providers/ProviderTestOutcome.swift",
    ]
}
