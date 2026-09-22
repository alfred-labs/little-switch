import SwiftUI

enum MenuTabContentLayout {
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 4
    static let actionRowHeight: CGFloat = 40
    static let verticalPadding: CGFloat = 8
    static let mappingPickerWidth: CGFloat = 170
    static let controlHeight: CGFloat = 28
}

/// The Grid measures one shared label column. This flexible middle column
/// puts every arrow halfway between that column and the fixed model control.
struct MenuMappingArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// Cycles in place because popup pickers cannot reliably open inside a
/// tracking NSMenu. The optimistic choice preserves rapid repeated clicks.
struct MenuModelStepper: View {
    let name: String
    let options: [MenuModelOption]
    let selection: MenuModelOption?
    let width: CGFloat
    let onSelect: @MainActor (MenuModelOption) async -> Void
    @State private var steppedSelection: MenuModelOption?
    @State private var selectionTask: Task<Void, Never>?
    @State private var selectionID: UUID?

    private var current: MenuModelOption? { steppedSelection ?? selection }

    var body: some View {
        HStack(spacing: 0) {
            chevron(
                "chevron.left",
                label: L10n.string("Previous model for \(name)")
            ) { step(-1) }
            Text(current?.label ?? GatewayUsageFormat.placeholder)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            chevron(
                "chevron.right",
                label: L10n.string("Next model for \(name)")
            ) { step(1) }
        }
        .frame(width: width, height: MenuTabContentLayout.controlHeight)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
        .disabled(options.isEmpty)
        .help(current?.label ?? L10n.string("No model selected"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.resource("Model for \(name)"))
    }

    private func chevron(
        _ symbol: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: MenuTabContentLayout.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int) {
        if let option = MenuModelSelection.step(options: options, from: current, by: delta) {
            steppedSelection = option
            let id = UUID()
            selectionID = id
            let previousTask = selectionTask
            selectionTask = Task {
                // Preserve click order even when committing a selection suspends.
                await previousTask?.value
                await onSelect(option)
                guard selectionID == id else { return }
                // Success and rejection both settle on the authoritative value.
                steppedSelection = nil
                selectionTask = nil
                selectionID = nil
            }
        }
    }
}

struct MenuModelLoadingPlaceholder: View {
    var body: some View {
        Text(L10n.resource("Loading models…"))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(
                width: MenuTabContentLayout.mappingPickerWidth,
                height: MenuTabContentLayout.controlHeight,
                alignment: .leading
            )
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
    }
}
