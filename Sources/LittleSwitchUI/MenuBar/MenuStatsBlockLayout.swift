import CoreGraphics

/// Shared geometry also sizes the fixed NSMenuItem hosting frames.
enum MenuStatsBlockLayout {
    static let horizontalPadding: CGFloat = 12
    static let metricLabelHeight: CGFloat = 14
    static let metricValueHeight: CGFloat = 20
    static let metricValueSpacing: CGFloat = 2
    static let metricRowSpacing: CGFloat = 10
    static let metricsHeight =
        (metricLabelHeight + metricValueSpacing + metricValueHeight) * 2 + metricRowSpacing
}
