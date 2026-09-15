import SwiftUI

/// Live, display-only counts with fixed geometry across polling updates.
struct GatewayQueueSummaryView: View {
    let runningCount: Int
    let waitingCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            counter("Running", value: runningCount) { runningIndicator }
            Divider().frame(height: 16)
            counter("Pending", value: waitingCount) {
                Image(systemName: "clock").foregroundStyle(.secondary)
            }
        }
        .frame(height: GatewayOverviewLayout.queueHeight)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.secondary, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.resource("Request queue"))
        .accessibilityValue(L10n.resource("\(runningCount) running, \(waitingCount) pending"))
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if runningCount == 0 {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
        } else if reduceMotion {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.accentColor)
        } else {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(.accentColor)
        }
    }

    private func counter<Icon: View>(
        _ title: String, value: Int, @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 7) {
            icon()
                .font(.system(size: 12))
                .frame(width: 12, height: 12)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            Text(value, format: .number)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(value)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: value)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
    }
}
