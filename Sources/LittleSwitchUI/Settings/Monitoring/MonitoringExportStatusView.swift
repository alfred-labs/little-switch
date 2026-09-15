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
                LabeledContent(L10n.string("Last accepted"), value: accepted.formatted(date: .omitted, time: .standard))
            }
            if let message = MonitoringExportStatusCopy.message(for: status) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let testResult, testResult != .disabled {
                Text(L10n.resource("Last test: \(MonitoringExportStatusCopy.message(for: testResult))"))
                    .textSelection(.enabled)
                    .help(L10n.resource("Result of the last synthetic export using the applied settings."))
            }
            if status.nextRetry != nil || status.queuedCount > 0 || status.droppedCount > 0 {
                DisclosureGroup(
                    L10n.string("Delivery details"),
                    isExpanded: $showsDeliveryDetails
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let retry = status.nextRetry {
                            LabeledContent(
                                L10n.string("Next retry"), value: retry.formatted(date: .omitted, time: .standard))
                        }
                        Text(
                            queueSummary(
                                queued: status.queuedCount,
                                bytes: status.queuedBytes,
                                dropped: status.droppedCount
                            )
                        )
                        .monospacedDigit()
                    }
                    .padding(.top, 6)
                }
                .disclosureGroupStyle(
                    SettingsDisclosureGroupStyle(
                        accessibilityHint: L10n.string(
                            "Show or hide \(title.lowercased()) delivery details."
                        ),
                        minimumHeaderHeight: SettingsLayout.disclosureDetailRowMinimumHeight
                    ) {}
                )
                .accessibilityLabel(L10n.resource("\(title) delivery details"))
            }
        }
        .font(SettingsLayout.Typography.supporting)
        .foregroundStyle(.secondary)
    }

    private func queueSummary(queued: Int, bytes: Int, dropped: UInt64) -> String {
        if bytes == 1 {
            return L10n.string("\(queued) queued · \(bytes) byte · \(dropped) dropped")
        }
        return L10n.string("\(queued) queued · \(bytes) bytes · \(dropped) dropped")
    }
}
