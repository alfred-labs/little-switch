import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct MonitoringDestinationFields<Options: View>: View {
    let title: String
    let placeholder: String
    @Binding var destination: MonitoringDestination
    @Binding var token: String
    @Binding var removeToken: Bool
    let pending: Bool
    let status: MonitoringSignalExportStatus
    let testResult: MonitoringExportTestOutcome?
    @ViewBuilder let options: Options
    @State private var isExpanded: Bool

    init(
        title: String,
        placeholder: String,
        destination: Binding<MonitoringDestination>,
        token: Binding<String>,
        removeToken: Binding<Bool>,
        pending: Bool,
        status: MonitoringSignalExportStatus,
        testResult: MonitoringExportTestOutcome?,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.placeholder = placeholder
        _destination = destination
        _token = token
        _removeToken = removeToken
        self.pending = pending
        self.status = status
        self.testResult = testResult
        self.options = options()
        _isExpanded = State(initialValue: destination.wrappedValue.enabled)
    }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        receiverURL
                        authentication
                        options
                    }
                    .padding(.top, 8)
                } label: {
                    Text(title)
                        .font(SettingsLayout.Typography.disclosureTitle)
                }
                .disclosureGroupStyle(
                    SettingsDisclosureGroupStyle(
                        accessibilityHint: L10n.string(
                            "Show or hide \(title.lowercased()) export settings."
                        )
                    ) {
                        headerControls
                    }
                )
                .accessibilityLabel(L10n.resource("\(title) export settings"))
                MonitoringExportStatusView(title: title, status: status, testResult: testResult)
                    .padding(.leading, 20)
            }
        }
        .onChange(of: destination.enabled) { _, enabled in isExpanded = enabled }
    }

    private var headerControls: some View {
        HStack(spacing: 10) {
            Text(MonitoringExportPresentation.title(for: status, pending: pending))
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
            Toggle(L10n.resource("Export \(title.lowercased())"), isOn: $destination.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint(L10n.string("Apply changes to update this export."))
        }
        .fixedSize()
    }

    private var receiverURL: some View {
        LabeledContent(L10n.string("Receiver URL")) {
            TextField(L10n.string("Receiver URL"), text: $destination.endpoint, prompt: Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.plain)
                .textContentType(.URL)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.resource("\(title) receiver URL"))
                .help(L10n.resource("Use the complete OTLP receiver URL, including its \(title.lowercased()) path."))
        }
        .frame(minHeight: SettingsLayout.disclosureRowMinimumHeight)
    }

    @ViewBuilder private var authentication: some View {
        LabeledContent(L10n.string("Authentication")) {
            Picker(L10n.resource("Authentication"), selection: $destination.authentication) {
                Text(L10n.resource("None")).tag(MonitoringAuthentication.none)
                Text(L10n.resource("Bearer token")).tag(MonitoringAuthentication.bearer)
            }
            .labelsHidden()
            .settingsMenuPicker()
            .monitoringControlColumn()
            .accessibilityLabel(L10n.resource("\(title) authentication"))
        }
        .frame(minHeight: SettingsLayout.disclosureRowMinimumHeight)
        if destination.authentication == .bearer {
            LabeledContent(L10n.string("Token")) {
                SecureField(L10n.string("Token"), text: $token, prompt: Text(tokenPlaceholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .monitoringControlColumn()
                    .disabled(removeToken)
                    .accessibilityLabel(L10n.resource("\(title) token"))
            }
        }
        if destination.credentialID != nil {
            LabeledContent(L10n.string("Saved token")) {
                Button(
                    removeToken
                        ? L10n.string("Keep saved token")
                        : L10n.string("Remove saved token")
                ) {
                    removeToken.toggle()
                    token = ""
                }
                .controlSize(.small)
                .accessibilityLabel(
                    L10n.resource(
                        "\(title): \(removeToken ? L10n.string("keep") : L10n.string("remove")) saved token"
                    )
                )
            }
        }
    }

    private var tokenPlaceholder: String {
        if removeToken {
            return L10n.string("Saved token will be removed on Apply")
        }
        return destination.credentialID == nil
            ? L10n.string("Bearer token")
            : L10n.string("Leave blank to keep the saved token")
    }
}
