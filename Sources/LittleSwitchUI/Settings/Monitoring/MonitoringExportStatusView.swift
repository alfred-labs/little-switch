import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

struct MonitoringExportStatusView: View {
    let title: String
    let status: MonitoringSignalExportStatus
    let testResult: MonitoringExportTestOutcome?
    @State private var showsDeliveryDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let accepted = status.lastAccepted {
                LabeledContent("Last accepted", value: accepted.formatted(date: .omitted, time: .standard))
            }
            if let message = status.configurationIssue?.message ?? status.failure?.message ?? status.warning?.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let testResult, testResult != .disabled {
                Text("Last test: \(testResult.message)")
                    .textSelection(.enabled)
                    .help("Result of the last synthetic export using the applied settings.")
            }
            if status.nextRetry != nil || status.queuedCount > 0 || status.droppedCount > 0 {
                DisclosureGroup("Delivery details", isExpanded: $showsDeliveryDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let retry = status.nextRetry {
                            LabeledContent("Next retry", value: retry.formatted(date: .omitted, time: .standard))
                        }
                        Text(
                            "\(status.queuedCount) queued · \(status.queuedBytes) bytes · \(status.droppedCount) dropped"
                        )
                        .monospacedDigit()
                    }
                    .padding(.top, 6)
                }
                .disclosureGroupStyle(
                    SettingsDisclosureGroupStyle(
                        accessibilityHint: "Show or hide \(title.lowercased()) delivery details.",
                        minimumHeaderHeight: SettingsLayout.disclosureDetailRowMinimumHeight
                    ) {}
                )
                .accessibilityLabel("\(title) delivery details")
            }
        }
        .font(SettingsLayout.Typography.supporting)
        .foregroundStyle(.secondary)
    }
}
