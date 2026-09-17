import LittleSwitchCommon
import SwiftUI

/// Pure arrow-key projection for the provider picker: RTL-aware offsets,
/// bounds, focus and the disabled state, verified without AX focus.
enum WebSearchProviderNavigation {
    static func selection(
        after direction: MoveCommandDirection,
        isEnabled: Bool,
        focusedProvider: WebSearchProvider?,
        layoutDirection: LayoutDirection
    ) -> WebSearchProvider? {
        guard isEnabled else { return nil }
        let offset: Int
        switch direction {
        case .left: offset = layoutDirection == .leftToRight ? -1 : 1
        case .right: offset = layoutDirection == .leftToRight ? 1 : -1
        default: return nil
        }
        let providers = WebSearchProvider.allCases
        guard let focused = focusedProvider,
            let current = providers.firstIndex(of: focused),
            providers.indices.contains(current + offset)
        else { return nil }
        return providers[current + offset]
    }
}
