import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

public struct SettingsView: View {
    @Bindable private var model: AppModel
    @State private var isSidebarVisible = true
    private let onLaunchAtLoginEnabled: @MainActor (Bool) async -> Void
    private let onOpenLoginItems: @MainActor () -> Void
    private let onModelIndicator: @MainActor (ModelIndicator) async -> Void
    private let onSaveProvider: @MainActor (ProviderInput) async -> ProviderSaveOutcome
    private let onTestProvider: @MainActor (ProviderInput) async -> ProviderTestOutcome
    private let onSaveWebSearch: @MainActor (WebSearchInput) async -> Bool
    private let onWebSearchDraft: @MainActor (WebSearchInput?) async -> Void
    private let onMonitoringDraft: @MainActor (MonitoringPendingSettings?) async -> Void
    private let onApplyMonitoring: @MainActor (MonitoringApplyInput) async -> Bool
    private let onTestMonitoring: @MainActor () async -> Void
    private let onRefreshProvider: @MainActor (UUID) async -> Void
    private let onDeleteProvider: @MainActor (UUID) async -> Void
    private let onMapping: @MainActor (String, ModelMapping?) async -> Void
    private let onAutoMode: @MainActor (Bool) async -> Void
    private let onApplyClaudeProducts:
        @MainActor (
            AppModel.ClaudePrimaryAction?,
            AppModel.ClaudeCodePrimaryAction?
        ) async -> Void
    private let onClaudeCodeDefault:
        @MainActor (
            String?,
            ClaudeCodeContextMode
        ) async -> Void
    private let onCodexExposure: @MainActor ([ModelMapping], Bool) async -> Void
    private let onCodexDefault: @MainActor (ModelMapping?) async -> Void
    private let onCodexAutoReview: @MainActor (ModelMapping?) async -> Void
    private let onConnectCodex: @MainActor () async -> Void
    private let onApplyCodex: @MainActor () async -> Void
    private let onOpenCodeDefault: @MainActor (ModelMapping?) async -> Void
    private let onConnectOpenCode: @MainActor () async -> Void
    private let onApplyOpenCode: @MainActor () async -> Void
    private let onRestoreOpenCode: @MainActor () async -> Void
    private let updater: any SoftwareUpdateProviding

    init(
        model: AppModel,
        updater: any SoftwareUpdateProviding,
        onLaunchAtLoginEnabled: @escaping @MainActor (Bool) async -> Void,
        onOpenLoginItems: @escaping @MainActor () -> Void,
        onModelIndicator: @escaping @MainActor (ModelIndicator) async -> Void,
        onSaveProvider: @escaping @MainActor (ProviderInput) async -> ProviderSaveOutcome,
        onTestProvider: @escaping @MainActor (ProviderInput) async -> ProviderTestOutcome,
        onSaveWebSearch: @escaping @MainActor (WebSearchInput) async -> Bool,
        onWebSearchDraft: @escaping @MainActor (WebSearchInput?) async -> Void,
        onRefreshProvider: @escaping @MainActor (UUID) async -> Void,
        onDeleteProvider: @escaping @MainActor (UUID) async -> Void,
        onMapping: @escaping @MainActor (String, ModelMapping?) async -> Void,
        onAutoMode: @escaping @MainActor (Bool) async -> Void,
        onApplyClaudeProducts:
            @escaping @MainActor (
                AppModel.ClaudePrimaryAction?,
                AppModel.ClaudeCodePrimaryAction?
            ) async -> Void,
        onClaudeCodeDefault:
            @escaping @MainActor (
                String?,
                ClaudeCodeContextMode
            ) async -> Void,
        onCodexExposure: @escaping @MainActor ([ModelMapping], Bool) async -> Void,
        onCodexDefault: @escaping @MainActor (ModelMapping?) async -> Void,
        onCodexAutoReview: @escaping @MainActor (ModelMapping?) async -> Void,
        onConnectCodex: @escaping @MainActor () async -> Void,
        onApplyCodex: @escaping @MainActor () async -> Void,
        onOpenCodeDefault: @escaping @MainActor (ModelMapping?) async -> Void,
        onConnectOpenCode: @escaping @MainActor () async -> Void,
        onApplyOpenCode: @escaping @MainActor () async -> Void,
        onRestoreOpenCode: @escaping @MainActor () async -> Void,
        onMonitoringDraft: @escaping @MainActor (MonitoringPendingSettings?) async -> Void = { _ in },
        onApplyMonitoring: @escaping @MainActor (MonitoringApplyInput) async -> Bool = { _ in false },
        onTestMonitoring: @escaping @MainActor () async -> Void = {}
    ) {
        self.model = model
        self.onLaunchAtLoginEnabled = onLaunchAtLoginEnabled
        self.onOpenLoginItems = onOpenLoginItems
        self.onModelIndicator = onModelIndicator
        self.onSaveProvider = onSaveProvider
        self.onTestProvider = onTestProvider
        self.onSaveWebSearch = onSaveWebSearch
        self.onWebSearchDraft = onWebSearchDraft
        self.onMonitoringDraft = onMonitoringDraft
        self.onApplyMonitoring = onApplyMonitoring
        self.onTestMonitoring = onTestMonitoring
        self.onRefreshProvider = onRefreshProvider
        self.onDeleteProvider = onDeleteProvider
        self.onMapping = onMapping
        self.onAutoMode = onAutoMode
        self.onApplyClaudeProducts = onApplyClaudeProducts
        self.onClaudeCodeDefault = onClaudeCodeDefault
        self.onCodexExposure = onCodexExposure
        self.onCodexDefault = onCodexDefault
        self.onCodexAutoReview = onCodexAutoReview
        self.onConnectCodex = onConnectCodex
        self.onApplyCodex = onApplyCodex
        self.onOpenCodeDefault = onOpenCodeDefault
        self.onConnectOpenCode = onConnectOpenCode
        self.onApplyOpenCode = onApplyOpenCode
        self.onRestoreOpenCode = onRestoreOpenCode
        self.updater = updater
    }

    private func sidebarRow(for section: AppModel.Section) -> some View {
        SettingsSidebarRow(section: section)
            .padding(.leading, SettingsLayout.sidebarRowAdditionalLeadingPadding)
            .tag(section)
            .listRowSeparator(.hidden)
    }

    public var body: some View {
        SettingsSplitView(isSidebarVisible: $isSidebarVisible) {
            VStack(spacing: 4) {
                SettingsSidebarIdentity()
                List(selection: $model.selectedSection) {
                    Section {
                        ForEach(
                            AppModel.SidebarGroup.common.sections + AppModel.SidebarGroup.backends.sections
                        ) { section in
                            sidebarRow(for: section)
                        }
                    }
                    Section {
                        ForEach(AppModel.SidebarGroup.apps.sections) { section in
                            sidebarRow(for: section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .environment(
                    \.defaultMinListRowHeight,
                    SettingsLayout.sidebarRowMinimumHeight
                )
            }
        } detail: {
            Group {
                switch model.selectedSection {
                case .common:
                    CommonSettingsView(
                        model: model,
                        updater: updater,
                        onLaunchAtLoginEnabled: onLaunchAtLoginEnabled,
                        onOpenLoginItems: onOpenLoginItems,
                        onModelIndicator: onModelIndicator
                    )
                case .providers:
                    ProvidersSettingsView(
                        model: model,
                        onSave: onSaveProvider,
                        onTest: onTestProvider,
                        onRefresh: onRefreshProvider,
                        onDelete: onDeleteProvider
                    )
                case .webSearch:
                    WebSearchSettingsView(
                        model: model,
                        onSave: onSaveWebSearch,
                        onDraft: onWebSearchDraft
                    )
                case .monitoring:
                    MonitoringSettingsView(
                        model: model,
                        onApply: onApplyMonitoring,
                        onDraft: onMonitoringDraft,
                        onTest: onTestMonitoring
                    )
                case .claude:
                    ClaudeSettingsView(
                        model: model,
                        onMapping: onMapping,
                        onAutoMode: onAutoMode,
                        onApplyAll: onApplyClaudeProducts,
                        onClaudeCodeDefault: onClaudeCodeDefault,
                    )
                case .codex:
                    CodexSettingsView(
                        model: model,
                        onExposure: onCodexExposure,
                        onDefault: onCodexDefault,
                        onAutoReview: onCodexAutoReview,
                        onConnect: onConnectCodex,
                        onApply: onApplyCodex
                    )
                case .openCode:
                    OpenCodeSettingsView(
                        model: model,
                        onDefault: onOpenCodeDefault,
                        onConnect: onConnectOpenCode,
                        onApply: onApplyOpenCode,
                        onRestore: onRestoreOpenCode
                    )
                }
            }
        }
        .font(SettingsLayout.Typography.rowLabel)
        .settingsWindowTitle(model.selectedSection.rawValue)
        .frame(
            minWidth: SettingsLayout.minimumWindowWidth,
            minHeight: SettingsLayout.minimumContentHeight
        )
        .alert(
            "LittleSwitch",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(L10n.resource("OK")) { model.errorMessage = nil }
        } message: {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
            } else {
                Text(L10n.resource("Unknown error"))
            }
        }
    }

}
