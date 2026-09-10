import Foundation
import LittleSwitchCore

/// One selectable model in a `MenuModelStepper`.
struct MenuModelOption: Equatable, Identifiable {
    let id: String
    let label: String
    let mapping: ModelMapping?
}

/// The pure stepping behind the menu's chevron steppers, kept out of the
/// coverage-excluded view files so the wrap-around and fallback rules stay
/// under test.
enum MenuModelSelection {
    /// The option `delta` steps away from `selection`, wrapping around the
    /// list. A selection missing from the list steps in from the matching
    /// end; an empty list offers nothing to select.
    static func step(
        options: [MenuModelOption],
        from selection: MenuModelOption?,
        by delta: Int
    ) -> MenuModelOption? {
        guard !options.isEmpty else {
            return nil
        }
        let next: Int
        if let index = options.firstIndex(where: { $0 == selection }) {
            next = ((index + delta) % options.count + options.count) % options.count
        } else {
            next = delta > 0 ? 0 : options.count - 1
        }
        return options[next]
    }
}
