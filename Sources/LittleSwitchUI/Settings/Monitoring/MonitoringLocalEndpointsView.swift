import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct MonitoringLocalEndpointsView: View {
    @Binding var configuration: MonitoringConfiguration
    let applied: MonitoringConfiguration
    let httpsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionContentSpacing) {
            HStack {
                SettingsSectionHeader(L10n.resource("Local access"))
                Spacer()
                Text(verbatim: "127.0.0.1:11436")
                    .font(SettingsLayout.Typography.monospacedValue)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                endpoint(
                    "Metrics",
                    path: "/metrics",
                    enabled: $configuration.exposeMetrics,
                    applied: applied.exposeMetrics
                )
                endpoint("Logs", path: "/logs", enabled: $configuration.exposeLogs, applied: applied.exposeLogs)
            }
            Text(L10n.resource("Available to apps on this Mac while LittleSwitch is running."))
                .settingsSupportingText()
        }
    }

    private func endpoint(_ title: String, path: String, enabled: Binding<Bool>, applied: Bool) -> some View {
        let presentation = MonitoringLocalEndpointPresentation(
            path: path, enabled: enabled.wrappedValue, appliedEnabled: applied, httpsAvailable: httpsAvailable
        )
        return HStack(spacing: 8) {
            Text(title)
            Text(path)
                .font(SettingsLayout.Typography.monospacedValue)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if presentation.isPending {
                Text(L10n.resource("Pending"))
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    .help(presentation.copyHelp)
            }
            Menu(L10n.resource("Copy URL")) {
                Button(L10n.resource("Copy HTTP URL")) { copy(presentation.httpURL) }
                if let httpsURL = presentation.httpsURL {
                    Button(L10n.resource("Copy HTTPS URL")) { copy(httpsURL) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!presentation.canCopy)
            .help(presentation.copyHelp)
            .accessibilityLabel(L10n.resource("Copy \(title.lowercased()) URL"))
            .accessibilityHint(presentation.copyHelp)
            Toggle(L10n.resource("Expose \(title.lowercased())"), isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint(L10n.string("Apply changes to update local access."))
        }
        .font(SettingsLayout.Typography.rowLabel)
        .frame(minHeight: SettingsLayout.disclosureRowMinimumHeight)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
