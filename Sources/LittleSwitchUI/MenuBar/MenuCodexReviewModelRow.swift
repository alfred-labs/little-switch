import LittleSwitchCore
import SwiftUI

/// Uses the coordinator's current draft, including an unavailable explicit choice.
struct MenuCodexReviewModelRow: View {
    @Bindable var model: AppModel
    let onSelect: @MainActor (ModelMapping?) async -> Void

    var body: some View {
        GridRow {
            Text("Auto-review")
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .frame(height: MenuTabContentLayout.rowHeight)
                .gridColumnAlignment(.leading)
                .help("Approval review model")
            MenuMappingArrow()
            MenuModelStepper(
                name: "Approval review model",
                options: options,
                selection: Binding(
                    get: { selection },
                    set: { option in Task { await onSelect(option?.mapping) } }
                ),
                width: MenuTabContentLayout.mappingPickerWidth
            )
            .disabled(model.isBusy || model.modelOptions.isEmpty)
            .accessibilityHint("Reviews requests for permissions outside the sandbox")
        }
    }

    private var options: [MenuModelOption] {
        [MenuModelOption(id: "same-as-default", label: "Same as default", mapping: nil)]
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
        return MenuModelOption(id: "unavailable", label: "Unavailable: \(mapping.modelID)", mapping: mapping)
    }
}
