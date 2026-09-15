import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct CommonSettingsView: View {
    @Bindable var model: AppModel
    let updater: any SoftwareUpdateProviding
    let onLaunchAtLoginEnabled: @MainActor (Bool) async -> Void
    let onOpenLoginItems: @MainActor () -> Void
    let onModelIndicator: @MainActor (ModelIndicator) async -> Void

    var body: some View {
        SettingsPage {
            SettingsSection(L10n.resource("Startup")) {
                SettingsCard {
                    launchAtLoginRow
                        .padding(.vertical, 6)
                }
            }
            SettingsSection(L10n.resource("Model indicator")) {
                SettingsCard {
                    modelIndicatorRow
                        .settingsRow()
                    LabeledContent(L10n.string("Preview")) {
                        Text(
                            ["Opus", model.configuration.modelIndicator.symbol].compactMap(\.self).joined(
                                separator: " ")
                        )
                        .foregroundStyle(.secondary)
                    }
                    .settingsRow()
                }
                Text(L10n.resource("Mark routed models in Claude's model picker."))
                    .settingsSupportingText()
                    .help(L10n.resource("The symbol changes display names only. Routing is unchanged."))
            }
            SettingsSection(L10n.resource("Software updates")) {
                SettingsCard {
                    softwareUpdateRow
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var modelIndicatorRow: some View {
        LabeledContent(L10n.string("Catalog symbol")) {
            Picker(
                L10n.resource("Catalog symbol"),
                selection: Binding(
                    get: { model.configuration.modelIndicator },
                    set: { indicator in
                        Task { await onModelIndicator(indicator) }
                    }
                )
            ) {
                ForEach(ModelIndicator.allCases, id: \.self) { indicator in
                    Text(indicator.localizedLabel).tag(indicator)
                }
            }
            .labelsHidden()
            .settingsMenuPicker(width: SettingsLayout.generalControlWidth)
            .disabled(model.isBusy)
        }
    }

    private var launchAtLoginRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.resource("Launch at login"))
                    .font(SettingsLayout.Typography.rowLabel)
                Text(L10n.resource("Open LittleSwitch automatically when you log in to your Mac."))
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                if model.launchAtLoginRequiresApproval {
                    Button(L10n.resource("Open Login Items…")) {
                        onOpenLoginItems()
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if model.isChangingLaunchAtLogin {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle(
                    L10n.resource("Launch at login"),
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { enabled in
                            Task {
                                await onLaunchAtLoginEnabled(enabled)
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!model.canChangeLaunchAtLogin)
                .accessibilityValue(model.launchAtLoginAccessibilityValue)
                .accessibilityHint(model.launchAtLoginAccessibilityHint)
            }
        }
    }

    private var softwareUpdateRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.resource("Install updates automatically"))
                    .font(SettingsLayout.Typography.rowLabel)
                switch updater.availability {
                case .enabled:
                    Text(
                        L10n.resource("Download and install updates in the background.")
                    )
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    if let lastChecked = updater.lastUpdateCheckDate {
                        Text(
                            L10n.resource(
                                "Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened)).")
                        )
                        .font(SettingsLayout.Typography.supporting)
                        .foregroundStyle(.secondary)
                    }
                    Button(L10n.resource("Check for Updates Now…")) {
                        updater.checkForUpdates(nil)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                case .disabled(let reason):
                    Text(reason)
                        .font(SettingsLayout.Typography.supporting)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if case .enabled = updater.availability {
                Toggle(
                    L10n.resource("Install updates automatically"),
                    isOn: Binding(
                        get: {
                            updater.automaticallyChecksForUpdates
                                && updater.automaticallyDownloadsUpdates
                        },
                        set: { enabled in
                            updater.automaticallyChecksForUpdates = enabled
                            updater.automaticallyDownloadsUpdates = enabled
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

}
