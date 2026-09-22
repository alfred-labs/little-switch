import SwiftUI

/// A local hover affordance that does not need to activate the menu-bar app
/// or change the system cursor owned by the foreground application.
struct ApplicationIconHover: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                Color.primary.opacity(highlightOpacity),
                in: .rect(cornerRadius: StatusMenuLayout.iconHoverCornerRadius)
            )
            .onContinuousHover { phase in
                switch phase {
                case .active: isHovered = true
                case .ended: isHovered = false
                }
            }
            .onDisappear { isHovered = false }
    }

    private var highlightOpacity: Double {
        guard isEnabled, isHovered else { return 0 }
        return contrast == .increased
            ? StatusMenuLayout.iconHoverHighContrastOpacity
            : StatusMenuLayout.iconHoverOpacity
    }
}
