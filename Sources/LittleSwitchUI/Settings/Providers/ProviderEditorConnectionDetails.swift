import LittleSwitchCommon
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
        DisclosureGroup(L10n.string("Connection details"), isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                LabeledContent(L10n.string("Responses format"), value: responsesFormat)
                if let wireProbe {
                    LabeledContent(L10n.string("Messages"), value: Self.availability(wireProbe.messages))
                    LabeledContent(L10n.string("Responses"), value: Self.availability(wireProbe.responses))
                    LabeledContent(L10n.string("Chat completions"), value: Self.availability(wireProbe.chatCompletions))
                    LabeledContent(L10n.string("Last probe")) {
                        Text(wireProbe.date.formatted(date: .abbreviated, time: .shortened))
                    }
                } else {
                    Text(L10n.resource("Test and save the connection to inspect its endpoints."))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(SettingsLayout.Typography.supporting)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .disclosureGroupStyle(
            SettingsDisclosureGroupStyle(
                accessibilityHint: L10n.string(
                    "Show or hide detected formats and endpoint availability"
                ),
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
            case .native: return L10n.string("Native /v1/responses · override")
            case .chatCompletions: return L10n.string("Chat completions · override")
            }
        }
        switch learnedVerdict {
        case .some(true):
            return L10n.string("Native /v1/responses · learned")
        case .some(false):
            return L10n.string("Chat completions · learned")
        case .none:
            return L10n.string("Not detected yet")
        }
    }

    private var probeSummary: String {
        guard let wireProbe else { return L10n.string("Not probed") }
        let count = [wireProbe.messages, wireProbe.responses, wireProbe.chatCompletions]
            .filter { $0 == .available }.count
        switch count {
        case 0: return L10n.string("No endpoints confirmed")
        case 1: return L10n.string("1 endpoint detected")
        default: return L10n.string("\(count) endpoints detected")
        }
    }

    private static func availability(_ availability: ProviderWireAvailability) -> String {
        switch availability {
        case .available: L10n.string("Available")
        case .absent: L10n.string("Unavailable")
        case .unknown: L10n.string("Inconclusive")
        }
    }
}
