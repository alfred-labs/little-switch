import SwiftUI

struct ProviderModelContextTable: View {
    @Binding var contexts: [ModelContextDraft]

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    Text("Model")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Capacity")
                        .frame(minWidth: SettingsLayout.ProviderEditor.contextCapacityWidth, alignment: .trailing)
                        .gridColumnAlignment(.trailing)
                    Text("1M in Claude")
                        .frame(width: SettingsLayout.ProviderEditor.contextToggleWidth, alignment: .trailing)
                        .gridColumnAlignment(.trailing)
                }
                .font(SettingsLayout.Typography.supporting)
                .foregroundStyle(.secondary)
                .frame(minHeight: SettingsLayout.disclosureDetailRowMinimumHeight)

                ForEach($contexts) { $context in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    ProviderModelContextRow(context: $context)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            HStack {
                Text("Model context")
                Spacer()
                Text(contexts.count == 1 ? "1 model" : "\(contexts.count) models")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("1M adds an optional model variant in Claude. Unavailable when detected capacity is below 1M.")
        }
    }
}

private struct ProviderModelContextRow: View {
    @Binding var context: ModelContextDraft

    var body: some View {
        GridRow {
            Text(context.id)
                .font(SettingsLayout.Typography.monospacedValue)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(context.id)
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
            .accessibilityLabel("Capacity for \(context.id)")
            .accessibilityValue(context.detail)
            .help(context.detail)

            Toggle(isOn: $context.declares1MManually) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .frame(width: SettingsLayout.ProviderEditor.contextToggleWidth, alignment: .trailing)
                .disabled(!context.allows1MOverride)
                .accessibilityLabel("Expose 1M context for \(context.id)")
                .help(
                    context.allows1MOverride
                        ? "Expose both the standard and [1m] Claude references"
                        : "Detected capacity is below 1M"
                )
        }
        .frame(minHeight: SettingsLayout.catalogModelRowMinimumHeight)
    }
}
