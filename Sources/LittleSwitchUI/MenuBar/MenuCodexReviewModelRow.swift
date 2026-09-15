import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI

/// Uses the coordinator's current draft, including an unavailable explicit choice.
struct MenuCodexReviewModelRow: View {
    @Bindable var model: AppModel
    let onSelect: @MainActor (ModelMapping?) async -> Void

    var body: some View {
        GridRow {
            Text(L10n.resource("Custom review"))
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .frame(height: MenuTabContentLayout.rowHeight)
                .gridColumnAlignment(.leading)
                .help(
                    L10n.resource(
                        "Reviews permission requests for custom models. Native OpenAI models keep Codex's own reviewer."
                    ))
            MenuMappingArrow()
            MenuModelStepper(
                name: L10n.string("Custom approval review model"),
                options: options,
                selection: Binding(
                    get: { selection },
                    set: { option in Task { await onSelect(option?.mapping) } }
                ),
                width: MenuTabContentLayout.mappingPickerWidth
            )
            .disabled(model.isBusy || model.modelOptions.isEmpty)
            .accessibilityHint(
                L10n.resource(
                    "Reviews permission requests for custom models. Native OpenAI models keep Codex's own reviewer."))
        }
    }

    private var options: [MenuModelOption] {
        [
            MenuModelOption(
                id: "same-as-default",
                label: L10n.string("Same as default"),
                mapping: nil
            )
        ]
            + model.modelOptions.map {
                MenuModelOption(id: $0.id, label: $0.label, mapping: $0.mapping)
            }
    }

    private var selection: MenuModelOption? {
        if let match = options.first(where: { $0.mapping == model.configuration.codex.autoReviewModel }) {
            return match
        }
        guard let mapping = model.configuration.codex.autoReviewModel else { return nil }
        // Keep the stale choice visible without offering it in the cycle.
        return MenuModelOption(
            id: "unavailable",
            label: L10n.string("Unavailable: \(mapping.modelID)"),
            mapping: mapping
        )
    }
}
