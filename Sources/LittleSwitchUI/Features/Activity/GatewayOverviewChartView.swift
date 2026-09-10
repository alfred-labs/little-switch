import SwiftUI

/// The selected period owns both this headline and the dashboard's metrics.
struct GatewayOverviewChartView: View {
    let stats: GatewayUsageStatsPresentation
    @Binding var hoveredIndex: Int?

    var body: some View {
        let period = stats.period(at: hoveredIndex)
        MenuTokenHistoryChart(
            points: stats.points,
            days: stats.dayDetails,
            axisLabels: stats.axisLabels,
            periodLabel: period.label,
            tokenTotal: period.tokenTotal,
            accessibilityValue: period.accessibilityValue,
            hoveredIndex: $hoveredIndex
        )
    }
}
