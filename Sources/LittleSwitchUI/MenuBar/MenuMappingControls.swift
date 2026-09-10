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
    @Binding var selection: MenuModelOption?
    let width: CGFloat
    @State private var steppedSelection: MenuModelOption?

    private var current: MenuModelOption? { steppedSelection ?? selection }

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", label: "Previous model for \(name)") { step(-1) }
            Text(current?.label ?? GatewayUsageFormat.placeholder)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            chevron("chevron.right", label: "Next model for \(name)") { step(1) }
        }
        .frame(width: width, height: MenuTabContentLayout.controlHeight)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
        .disabled(options.isEmpty)
        .help(current?.label ?? "No model selected")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model for \(name)")
        .onChange(of: selection) { _, _ in steppedSelection = nil }
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
            selection = option
        }
    }
}

struct MenuModelLoadingPlaceholder: View {
    var body: some View {
        Text("Loading models…")
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
