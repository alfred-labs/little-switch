import SwiftUI

enum StatusMenuSwitchTrack {
    static let width: CGFloat = 36
    static let height: CGFloat = 16
    static let thumb: CGFloat = 14
    static let inset: CGFloat = 1
    private static let travel = width - thumb - inset * 2

    static func draggedValue(isOn: Bool, translation: CGFloat, layoutDirection: LayoutDirection) -> Bool {
        position(isOn: isOn, translation: translation, layoutDirection: layoutDirection) > travel / 2
    }

    static func thumbOffset(isOn: Bool, translation: CGFloat, layoutDirection: LayoutDirection) -> CGFloat {
        position(isOn: isOn, translation: translation, layoutDirection: layoutDirection)
            * (layoutDirection == .leftToRight ? 1 : -1)
    }

    private static func position(isOn: Bool, translation: CGFloat, layoutDirection: LayoutDirection) -> CGFloat {
        let offset = translation * (layoutDirection == .leftToRight ? 1 : -1)
        return min(travel, max(0, (isOn ? travel : 0) + offset))
    }
}
