import SwiftUI

/// Display-only Overview: live queue, token history and the inspected period's metrics.
struct GatewayActivityDashboardView: View {
    let runningCount: Int
    let waitingCount: Int
    let stats: GatewayUsageStatsPresentation?
    var webSearch: GatewayWebSearchRow?
    @State private var hoveredIndex: Int?

    static func height(stats: GatewayUsageStatsPresentation?) -> CGFloat {
        var height = GatewayOverviewLayout.verticalPadding * 2 + GatewayOverviewLayout.queueHeight
        if stats != nil {
            height +=
                MenuStatsBlockLayout.metricsHeight
                + GatewayOverviewLayout.chartHeight
                + GatewayOverviewLayout.sectionSpacing * 2
        }
        return height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayOverviewLayout.sectionSpacing) {
            GatewayQueueSummaryView(runningCount: runningCount, waitingCount: waitingCount)
                .accessibilityHint(
                    webSearch.map { "Web search via \($0.engineName), \($0.callCount) calls today" } ?? ""
                )
            if let stats {
                GatewayOverviewChartView(stats: stats, hoveredIndex: $hoveredIndex)
                MenuMetricsGridView(metrics: stats.period(at: hoveredIndex).metrics)
            }
        }
        .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
        .padding(.vertical, GatewayOverviewLayout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gateway activity")
        .accessibilityHint("Gateway requests and usage")
        .onDisappear { hoveredIndex = nil }
    }
}
