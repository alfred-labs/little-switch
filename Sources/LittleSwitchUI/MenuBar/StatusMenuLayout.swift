import CoreGraphics

enum StatusMenuLayout {
    static let width: CGFloat = 320
    static let switcherHeight: CGFloat = 40
    static let applicationRowHeight: CGFloat = 40
    static let applicationRowSpacing: CGFloat = 4
    static let applicationBlockVerticalPadding: CGFloat = 8
    static let applicationBlockHeight =
        applicationRowHeight * 4 + applicationRowSpacing * 3 + applicationBlockVerticalPadding * 2
    static let iconSize: CGFloat = 20
    static let titleFontSize: CGFloat = 12
    static let counterFontSize: CGFloat = 11
    static let horizontalPadding: CGFloat = 12
    static let contentSpacing: CGFloat = 9
}
