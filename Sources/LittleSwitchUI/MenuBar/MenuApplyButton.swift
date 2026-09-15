import AppKit
import SwiftUI

/// The menu's compact Return key. The control stays a SwiftUI Button so
/// disabled state, focus, and accessibility keep their native semantics.
struct MenuApplyButton: View {
    let action: MenuApplyAction

    var body: some View {
        Button {
            action()
        } label: {
            Label(L10n.resource("Apply changes"), systemImage: "return")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(MenuApplyKeycapStyle())
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!action.isEnabled)
        .help(L10n.resource("Apply changes (Return)"))
        .accessibilityHint(L10n.string("Applies changes in this tab"))
    }
}

private struct MenuApplyKeycapStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let highlighted = isEnabled && isHovered
        configuration.label
            .foregroundStyle(
                highlighted ? Color(nsColor: .controlBackgroundColor) : Color.primary
            )
            .frame(width: 33, height: 27)
            .background {
                shape
                    .fill(highlighted ? Color.primary : Color(nsColor: .controlColor))
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18),
                        radius: 0,
                        y: configuration.isPressed ? 0 : 2
                    )
            }
            .overlay {
                shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.6 : 0.2))
            }
            .overlay {
                if isFocused {
                    shape.inset(by: -3).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(shape)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.38)
            .onHover { isHovered = $0 }
    }
}
