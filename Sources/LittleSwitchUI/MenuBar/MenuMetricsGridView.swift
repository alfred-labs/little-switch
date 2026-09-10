import SwiftUI

struct MenuMetricsGridView: View {
    let metrics: [GatewayUsageStatsPresentation.Metric]
    private static let columnCount = 3

    private struct Row: Identifiable {
        let metrics: [GatewayUsageStatsPresentation.Metric]
        var id: String { metrics[0].id }
    }

    private var rows: [Row] {
        stride(from: 0, to: metrics.count, by: Self.columnCount).map {
            Row(metrics: Array(metrics[$0..<min($0 + Self.columnCount, metrics.count)]))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MenuStatsBlockLayout.metricRowSpacing) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(row.metrics) { metric in
                        MenuMetricValue(
                            metric: metric,
                            alignment: alignment(for: metric, in: row)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func alignment(
        for metric: GatewayUsageStatsPresentation.Metric, in row: Row
    ) -> HorizontalAlignment {
        if metric.id == row.metrics.first?.id { return .leading }
        if metric.id == row.metrics.last?.id {
            return .trailing
        }
        return .center
    }
}

private struct MenuMetricValue: View {
    let metric: GatewayUsageStatsPresentation.Metric
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: MenuStatsBlockLayout.metricValueSpacing) {
            Text(metric.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(height: MenuStatsBlockLayout.metricLabelHeight, alignment: .bottom)
            Text(metric.value)
                .font(.system(size: metric.isLeading ? 17 : 15, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: MenuStatsBlockLayout.metricValueHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.accessibilityValue)
        .help("\(metric.title): \(metric.accessibilityValue)")
    }
}
