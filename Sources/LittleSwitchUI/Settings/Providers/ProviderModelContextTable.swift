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
                    Text(L10n.resource("Capacity"))
                        .frame(minWidth: SettingsLayout.ProviderEditor.contextCapacityWidth, alignment: .trailing)
                        .gridColumnAlignment(.trailing)
                    Text(L10n.resource("1M in Claude"))
                        .frame(width: SettingsLayout.ProviderEditor.contextToggleWidth, alignment: .trailing)
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
            Text(
                L10n.resource(
                    "1M adds an optional model variant in Claude. Unavailable when detected capacity is below 1M."))
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
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.capacityText)
                    .monospacedDigit()
                if let note = context.capacityNote {
                    Text(note)
                        .font(SettingsLayout.Typography.supporting)
                }
            }
            .font(SettingsLayout.Typography.rowLabel)
            .foregroundStyle(context.isValid ? Color.secondary : Color.red)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: SettingsLayout.ProviderEditor.contextCapacityWidth, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.resource("Capacity for \(context.id)"))
            .accessibilityValue(context.detail)
            .help(context.detail)

            Toggle(isOn: $context.declares1MManually) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .frame(width: SettingsLayout.ProviderEditor.contextToggleWidth, alignment: .trailing)
                .disabled(!context.allows1MOverride)
                .accessibilityLabel(L10n.resource("Expose 1M context for \(context.id)"))
                .help(

                    context.allows1MOverride
                        ? L10n.resource(
                            "Expose both the standard and [1m] Claude references"
                        )
                        : L10n.resource("Detected capacity is below 1M")
                )
        }
        .frame(minHeight: SettingsLayout.catalogModelRowMinimumHeight)
    }
}
