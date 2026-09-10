import CoreGraphics

/// Overview's layout also sizes its fixed-frame native menu host.
enum GatewayOverviewLayout {
    static let verticalPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 16
    static let queueHeight: CGFloat = 32
    static let chartCaptionHeight: CGFloat = 14
    static let chartTotalFontSize: CGFloat = 24
    static let chartTotalHeight: CGFloat = 30
    static let chartBarsHeight: CGFloat = 92
    static let chartAxisHeight: CGFloat = 12
    static let chartSpacing: CGFloat = 6

    static let chartHeight =
        chartCaptionHeight + chartTotalHeight
        + chartBarsHeight + chartAxisHeight + chartSpacing * 3
}
