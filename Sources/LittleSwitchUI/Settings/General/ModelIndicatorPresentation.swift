import Foundation
import LittleSwitchCommon

extension ModelIndicator {
    var localizedLabel: LocalizedStringResource {
        switch self {
        case .none: L10n.resource("None")
        case .swap: L10n.resource("Swap ⇄")
        case .equilibrium: L10n.resource("Equilibrium ⇌")
        case .routed: L10n.resource("Routed ⇢")
        case .mapsTo: L10n.resource("Maps to ↦")
        }
    }
}
