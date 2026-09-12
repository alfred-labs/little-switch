import LittleSwitchCore
import SwiftUI

/// Read-only diagnostics are available on demand, with inconclusive probes
/// kept distinct from routes confirmed absent.
struct ProviderEditorConnectionDetails: View {
    @Binding var isExpanded: Bool
    let responsesWireOverride: ProviderResponsesWireOverride?
    let learnedVerdict: Bool?
    let wireProbe: ProviderWireProbe?

    var body: some View {
        DisclosureGroup("Connection details", isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                LabeledContent("Responses format", value: responsesFormat)
                if let wireProbe {
                    LabeledContent("Messages", value: Self.availability(wireProbe.messages))
                    LabeledContent("Responses", value: Self.availability(wireProbe.responses))
                    LabeledContent("Chat completions", value: Self.availability(wireProbe.chatCompletions))
                    LabeledContent("Last probe") {
                        Text(wireProbe.date.formatted(date: .abbreviated, time: .shortened))
                    }
                } else {
                    Text("Test and save the connection to inspect its endpoints.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(SettingsLayout.Typography.supporting)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .disclosureGroupStyle(
            SettingsDisclosureGroupStyle(
                accessibilityHint: "Show or hide detected formats and endpoint availability",
                minimumHeaderHeight: SettingsLayout.disclosureDetailRowMinimumHeight
            ) {
                Text(probeSummary)
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
            }
        )
    }

    private var responsesFormat: String {
        if let responsesWireOverride {
            switch responsesWireOverride {
            case .native: return "Native /v1/responses · override"
            case .chatCompletions: return "Chat completions · override"
            }
        }
        switch learnedVerdict {
        case .some(true):
            return "Native /v1/responses · learned"
        case .some(false):
            return "Chat completions · learned"
        case .none:
            return "Not detected yet"
        }
    }

    private var probeSummary: String {
        guard let wireProbe else { return "Not probed" }
        let count = [wireProbe.messages, wireProbe.responses, wireProbe.chatCompletions]
            .filter { $0 == .available }.count
        switch count {
        case 0: return "No endpoints confirmed"
        case 1: return "1 endpoint detected"
        default: return "\(count) endpoints detected"
        }
    }

    private static func availability(_ availability: ProviderWireAvailability) -> String {
        switch availability {
        case .available: "Available"
        case .absent: "Unavailable"
        case .unknown: "Inconclusive"
        }
    }
}
