import SwiftUI

struct ProviderModelContextTable: View {
    @Binding var contexts: [ModelContextDraft]
    var imagePresentations: [String: ProviderModelImageInputPresentation] = [:]

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    Text(L10n.resource("Model"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.resource("Detected capacity"))
                        .frame(minWidth: SettingsLayout.ProviderEditor.contextCapacityWidth, alignment: .trailing)
                        .gridColumnAlignment(.trailing)
                    Text(L10n.resource("1M in Claude"))
                        .frame(width: SettingsLayout.ProviderEditor.contextClaudeWidth, alignment: .trailing)
                        .gridColumnAlignment(.trailing)
                }
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
                .frame(minHeight: SettingsLayout.disclosureDetailRowMinimumHeight)

                ForEach($contexts) { $context in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    ProviderModelContextRow(context: $context, imagePresentation: imagePresentations[context.id])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            HStack {
                Text(L10n.resource("Model context"))
                Spacer()
                Text(
                    contexts.count == 1
                        ? L10n.resource("1 model")
                        : L10n.resource("\(contexts.count) models")
                )
                .foregroundStyle(.secondary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if contexts.contains(where: { !$0.allows1MOverride }) {
                    Text(
                        L10n.resource(
                            "Claude offers 1M automatically when detected capacity reaches 1,000,000 tokens."))
                }
                if contexts.contains(where: \.allows1MOverride) {
                    Text(
                        L10n.resource("Only force 1M if the model supports it. Its actual capacity remains unverified.")
                    )
                }
            }
        }
    }
}

private struct ProviderModelContextRow: View {
    @Binding var context: ModelContextDraft
    let imagePresentation: ProviderModelImageInputPresentation?

    var body: some View {
        GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.id)
                    .font(SettingsLayout.Typography.monospacedValue)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(context.id)
                if let imagePresentation {
                    Text(imagePresentation.title)
                        .font(SettingsLayout.Typography.supporting)
                        .foregroundStyle(.secondary)
                        .help(imagePresentation.help)
                        .accessibilityHint(imagePresentation.help)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(context.capacityText)
                .monospacedDigit()
                .font(SettingsLayout.Typography.rowLabel)
                .foregroundStyle(context.isValid ? Color.secondary : Color.red)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: SettingsLayout.ProviderEditor.contextCapacityWidth, alignment: .trailing)
                .accessibilityLabel(L10n.resource("Capacity for \(context.id)"))
                .accessibilityValue(context.capacityText)
                .help(context.detail)

            claudeContext
                .font(SettingsLayout.Typography.rowLabel)
                .frame(width: SettingsLayout.ProviderEditor.contextClaudeWidth, alignment: .trailing)
        }
        .frame(minHeight: SettingsLayout.catalogModelRowMinimumHeight)
    }

    @ViewBuilder
    private var claudeContext: some View {
        switch context.claude1MState {
        case .automatic:
            Label(L10n.resource("Automatic"), systemImage: "checkmark")
                .fixedSize()
                .accessibilityLabel(L10n.resource("1M context for \(context.id)"))
                .accessibilityValue(L10n.resource("Automatic"))
        case .unavailable:
            Text(L10n.resource("Unavailable"))
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel(L10n.resource("1M context for \(context.id)"))
                .accessibilityValue(L10n.resource("Unavailable"))
                .accessibilityHint(L10n.resource("Detected capacity is below 1M"))
                .help(L10n.resource("Detected capacity is below 1M"))
        case .manual:
            Toggle(L10n.resource("Force"), isOn: $context.declares1MManually)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(L10n.resource("Force 1M context in Claude for \(context.id)"))
                .accessibilityHint(
                    L10n.resource("Only force 1M if the model supports it. Its actual capacity remains unverified.")
                )
                .help(L10n.resource("Only force 1M if the model supports it. Its actual capacity remains unverified."))
        }
    }
}
