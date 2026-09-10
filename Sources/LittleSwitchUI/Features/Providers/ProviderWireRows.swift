import LittleSwitchCore
import SwiftUI

/// The Responses-wire rows of the provider editor: the wire picker users can
/// pin, the learned verdict while automatic, and the last save-time probe of
/// the provider's endpoint routes.
struct ProviderWireRows: View {
    @Binding var responsesWireOverride: ProviderResponsesWireOverride?
    /// Learned Responses wire from the gateway ledger, when probed: true =
    /// native /v1/responses, false = chat-completions adapter. Nil = never
    /// probed.
    let learnedVerdict: Bool?
    let wireProbe: ProviderWireProbe?
    let namespaceProbe: ProviderNamespaceProbe?

    var body: some View {
        Picker("Responses wire", selection: $responsesWireOverride) {
            Text("Automatic").tag(ProviderResponsesWireOverride?.none)
            Text("Native /v1/responses").tag(
                Optional(ProviderResponsesWireOverride.native)
            )
            Text("Chat completions").tag(
                Optional(ProviderResponsesWireOverride.chatCompletions)
            )
        }
        .settingsMenuPicker()
        if responsesWireOverride == nil {
            LabeledContent("Detected") {
                Text(learnedText)
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        if let wireProbe {
            LabeledContent("Endpoints") {
                Text(Self.endpointSummary(wireProbe))
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .help(
                "Probed on save with empty requests: a validation rejection proves a route, 404 proves its absence. "
                    + "Last probe: "
                    + wireProbe.date.formatted(date: .abbreviated, time: .shortened)
            )
        }
        if let namespaceProbe {
            LabeledContent("Namespaces") {
                Text(Self.namespaceSummary(namespaceProbe))
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .help(
                "Probed on save with one tiny forced call: the backend answered "
                    + Self.namespaceExplanation(namespaceProbe.verdict)
                    + " Last probe: "
                    + namespaceProbe.date.formatted(date: .abbreviated, time: .shortened)
            )
        }
    }

    private var learnedText: String {
        switch learnedVerdict {
        case .some(true):
            "Native /v1/responses · learned"
        case .some(false):
            "Chat completions · learned"
        case .none:
            "Not detected yet"
        }
    }

    /// One-line probe summary, most decisive routes first: messages for
    /// Claude, responses and chat for Codex. A firewall answered "?" rows;
    /// the summary must not pretend those routes were measured.
    private static func endpointSummary(_ probe: ProviderWireProbe) -> String {
        [
            "Messages \(symbol(probe.messages))",
            "Responses \(symbol(probe.responses))",
            "Chat \(symbol(probe.chatCompletions))",
        ].joined(separator: " · ")
    }

    private static func symbol(_ availability: ProviderWireAvailability) -> String {
        switch availability {
        case .available:
            "✓"
        case .absent:
            "✗"
        case .unknown:
            "?"
        }
    }

    private static func namespaceSummary(_ probe: ProviderNamespaceProbe) -> String {
        var summary = "\(symbol(probe.verdict)) \(label(probe.verdict))"
        if let model = probe.model {
            summary += " · \(model)"
        }
        return summary
    }

    private static func symbol(_ verdict: ProviderNamespaceVerdict) -> String {
        switch verdict {
        case .restored:
            "✓"
        case .rejected:
            "✗"
        case .silentlyDropped, .unknown:
            "?"
        }
    }

    private static func label(_ verdict: ProviderNamespaceVerdict) -> String {
        switch verdict {
        case .restored:
            "Native"
        case .silentlyDropped:
            "Not called"
        case .rejected:
            "Rejected"
        case .unknown:
            "Unknown"
        }
    }

    private static func namespaceExplanation(_ verdict: ProviderNamespaceVerdict) -> String {
        switch verdict {
        case .restored:
            "with the namespaced pair, so group tools are served natively. "
        case .silentlyDropped:
            "by accepting the request without calling the probe tool. "
        case .rejected:
            "by rejecting the namespace shape. "
        case .unknown:
            "inconclusively — auth, quota, or a server error can look like this. "
        }
    }
}
