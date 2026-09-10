import SwiftUI

/// One token-history treatment for Overview and the client tabs.
struct MenuTokenHistoryChart: View {
    let points: [Int]
    let days: [GatewayUsageStatsPresentation.DayDetail]
    let axisLabels: [String]
    let periodLabel: String
    let tokenTotal: String
    let accessibilityValue: String
    @Binding var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayOverviewLayout.chartSpacing) {
            HStack {
                Text("Token history")
                Spacer(minLength: 0)
                Text(periodLabel)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(height: GatewayOverviewLayout.chartCaptionHeight)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(tokenTotal)
                    .font(.system(size: GatewayOverviewLayout.chartTotalFontSize, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(height: GatewayOverviewLayout.chartTotalHeight)
            MenuTokenSeriesPlot(
                points: points,
                days: days,
                peak: points.reduce(0, max),
                height: GatewayOverviewLayout.chartBarsHeight,
                hoveredIndex: $hoveredIndex
            )
            HStack {
                ForEach(axisLabels, id: \.self) { label in
                    Text(label)
                        .frame(maxWidth: .infinity, alignment: axisAlignment(for: label))
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(height: GatewayOverviewLayout.chartAxisHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token history")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard !points.isEmpty else {
                hoveredIndex = nil
                return
            }
            let lastIndex = points.count - 1
            let current = min(max(hoveredIndex ?? lastIndex, 0), lastIndex)
            switch direction {
            case .increment: hoveredIndex = min(current + 1, lastIndex)
            case .decrement: hoveredIndex = max(current - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Show 30 days") { hoveredIndex = nil }
        .help("\(accessibilityValue). Inspect a day to see its token usage.")
    }

    private func axisAlignment(for label: String) -> Alignment {
        if label == axisLabels.first { return .leading }
        if label == axisLabels.last { return .trailing }
        return .center
    }
}
