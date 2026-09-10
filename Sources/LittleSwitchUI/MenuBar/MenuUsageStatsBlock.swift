import SwiftUI

/// Client totals sit below the chart, with no repeated daily detail rows.
struct MenuUsageStatsBlock: View {
    static let fixedHeight: CGFloat =
        GatewayOverviewLayout.chartHeight
        + GatewayOverviewLayout.sectionSpacing
        + MenuStatsBlockLayout.metricsHeight

    let stats: GatewayUsageStatsPresentation
    @State private var hoveredIndex: Int?

    var body: some View {
        let period = stats.period(at: hoveredIndex)
        VStack(alignment: .leading, spacing: GatewayOverviewLayout.sectionSpacing) {
            MenuTokenHistoryChart(
                points: stats.points,
                days: stats.dayDetails,
                axisLabels: stats.axisLabels,
                periodLabel: period.label,
                tokenTotal: period.tokenTotal,
                accessibilityValue: period.accessibilityValue,
                hoveredIndex: $hoveredIndex
            )
            MenuMetricsGridView(metrics: period.metrics)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { hoveredIndex = nil }
    }
}
