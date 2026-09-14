enum CoverageBoundaryPolicy {
    private struct Boundary {
        let declaration: String
        let focused: String
        let former: String
    }

    static var rules: [RepositoryTextRule] {
        let ui = "Sources/LittleSwitchUI/"
        let core = "Sources/LittleSwitchCore/"
        let transport = "Sources/LittleSwitchTransport/"
        let boundaries = [
            Boundary(
                declaration: #"\bstruct MonitoringSettingsDraft\b"#,
                focused: ui + "Settings/Monitoring/MonitoringSettingsDraft.swift",
                former: ui + "Settings/Monitoring/MonitoringSettingsView.swift"),
            Boundary(
                declaration: #"\bpublic struct MonitoringApplyInput\b"#,
                focused: ui + "Settings/Monitoring/MonitoringSettingsDraft.swift",
                former: ui + "Settings/Monitoring/MonitoringDestinationFields.swift"),
            Boundary(
                declaration: #"\bpublic struct KeychainSecretStore\b"#,
                focused: core + "Security/Keychain/KeychainSecretStore.swift",
                former: core + "Security/Secrets/SecretStore.swift"),
            Boundary(
                declaration: #"\bpublic final class AsyncHTTPTransport\b"#,
                focused: transport + "HTTP/AsyncHTTPTransport.swift",
                former: core + "Providers/Catalog/ProviderClient.swift"),
            Boundary(
                declaration: #"\bpublic final class AsyncHTTPTransport\b"#,
                focused: transport + "HTTP/AsyncHTTPTransport.swift",
                former: transport + "HTTP/UpstreamTransport.swift"),
            Boundary(
                declaration: #"\bpublic final class AsyncHTTPTransport\b"#,
                focused: transport + "HTTP/AsyncHTTPTransport.swift",
                former: transport + "HTTP/ShutdownOnceUpstreamTransport.swift"),
            Boundary(
                declaration: #"\benum SettingsLayout\b"#,
                focused: ui + "Settings/Shared/SettingsLayout.swift",
                former: ui + "Settings/Root/SettingsChrome.swift"),
            Boundary(
                declaration: #"\bstruct ProviderDraft\b"#,
                focused: ui + "Settings/Providers/ProviderDraft.swift",
                former: ui + "Settings/Providers/ProviderEditor.swift"),
            Boundary(
                declaration: #"\bstruct WebSearchDraft\b"#,
                focused: ui + "Settings/Search/WebSearchSettingsDraft.swift",
                former: ui + "Settings/Search/WebSearchSettingsView.swift"),
            Boundary(
                declaration: #"\benum StatusMenuCopy\b"#,
                focused: ui + "MenuBar/StatusMenuCopy.swift",
                former: ui + "MenuBar/MenuStatusView.swift"),
            Boundary(
                declaration: #"\bstruct StatusItemVisibilityRecoveryPolicy\b"#,
                focused: ui + "MenuBar/StatusItemVisibilityPolicy.swift",
                former: ui + "MenuBar/StatusItemVisibilityRecovery.swift"),
            Boundary(
                declaration: #"\bstruct StatusItemVisibilitySnapshot\b"#,
                focused: ui + "MenuBar/StatusItemVisibilityPolicy.swift",
                former: ui + "MenuBar/StatusItemVisibilityRecovery.swift"),
            Boundary(
                declaration: #"\benum GatewayActivityMenuItemRenderer\b"#,
                focused: ui + "Features/Activity/GatewayActivityMenuItemRenderer.swift",
                former: ui + "MenuBar/StatusItemVisibilityRecovery.swift"),
            Boundary(
                declaration: #"\bstruct GatewayActivityPollingUpdate\b"#,
                focused: ui + "Features/Activity/GatewayActivityPollingUpdate.swift",
                former: ui + "Features/Activity/LittleSwitchApplicationDelegateGatewayActivity.swift"),
            Boundary(
                declaration: #"\bpackage struct NSWorkspaceApplicationProcessDiscovery\b"#,
                focused: ui + "Platform/ProcessHandoff/ApplicationHandoffSystem.swift",
                former: ui + "Platform/ProcessHandoff/ApplicationHandoff.swift"),
            Boundary(
                declaration: #"\bpackage struct ContinuousApplicationHandoffTiming\b"#,
                focused: ui + "Platform/ProcessHandoff/ApplicationHandoffSystem.swift",
                former: ui + "Platform/ProcessHandoff/ApplicationHandoff.swift"),
            Boundary(
                declaration: #"\bpackage final class ApplicationHandoffSignalMonitor\b"#,
                focused: ui + "Platform/ProcessHandoff/ApplicationHandoffSystem.swift",
                former: ui + "Platform/ProcessHandoff/ApplicationHandoff.swift"),
            Boundary(
                declaration: #"\bstruct OSLogTrafficLogger\b"#,
                focused: ui + "Features/Activity/Traffic/OSLogTrafficLogger.swift",
                former: ui + "Features/Activity/Traffic/TrafficLogSupport.swift"),
        ]
        return boundaries.flatMap { boundary in
            [
                RepositoryTextRule(boundary.focused, required: [boundary.declaration]),
                RepositoryTextRule(boundary.former, forbidden: [boundary.declaration]),
            ]
        } + [
            RepositoryTextRule(
                ui + "Platform/ProcessHandoff/ApplicationHandoff.swift",
                required: [#"\bpackage struct POSIXApplicationProcessSignaler\b"#],
                forbidden: [#"\bNSRunningApplication\b"#]),
            RepositoryTextRule(
                ui + "Platform/ProcessHandoff/ApplicationHandoffSystem.swift",
                required: [
                    #"extension POSIXApplicationProcessSignaler\s*\{\s*package init\(\)"#,
                    #"\bNSRunningApplication\b"#, #"\bDarwin\.kill\b"#,
                ]),
        ]
    }
}
