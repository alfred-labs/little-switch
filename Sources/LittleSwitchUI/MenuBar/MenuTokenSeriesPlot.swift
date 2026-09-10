import SwiftUI

/// Shared bar geometry and pointer tracking; each surface owns its caption.
struct MenuTokenSeriesPlot: View {
    let points: [Int]
    let days: [GatewayUsageStatsPresentation.DayDetail]
    let peak: Int
    let height: CGFloat
    @Binding var hoveredIndex: Int?
    @Environment(\.colorSchemeContrast) private var contrast

    private struct Bar: Identifiable {
        let id: String
        let index: Int
        let value: Int
    }

    private var bars: [Bar] {
        zip(days, points).enumerated().map {
            Bar(id: $0.element.0.id, index: $0.offset, value: $0.element.1)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(bars) { bar in
                let ratio = peak > 0 ? Double(bar.value) / Double(peak) : 0
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(barColor(bar, ratio: ratio))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, ratio * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(contrast == .increased ? 0.5 : 0.15))
                .frame(height: 1)
        }
        .background {
            GeometryReader { geometry in
                if let hoveredIndex {
                    let slot = geometry.size.width / CGFloat(max(points.count, 1))
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: max(2, slot - 2))
                        .offset(x: slot * CGFloat(hoveredIndex) + 1)
                }
            }
        }
        .overlay {
            GeometryReader { geometry in
                MouseLocationReader { location in
                    let selection = location.map {
                        MenuSeriesGeometry.barIndex(
                            at: $0.x, width: geometry.size.width, dayCount: points.count
                        )
                    }
                    if selection != hoveredIndex { hoveredIndex = selection }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func barColor(_ bar: Bar, ratio: Double) -> Color {
        guard bar.value > 0 else { return .clear }
        if bar.index == hoveredIndex || bar.index == points.count - 1 { return .accentColor }
        return Color.primary.opacity(contrast == .increased ? 0.65 : 0.22 + ratio * 0.26)
    }
}
