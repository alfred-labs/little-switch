import SwiftUI

struct MonitoringMetricIntervalPicker: View {
    @Binding var value: Int

    private static let presets = [5, 10, 15, 30, 60, 120, 300]

    var body: some View {
        LabeledContent(L10n.string("Export every")) {
            Picker(L10n.resource("Metrics export interval"), selection: $value) {
                ForEach(Self.presets, id: \.self) { seconds in
                    Text(Self.title(for: seconds)).tag(seconds)
                }
                // Preserve an existing non-preset interval until a new value is selected.
                if !Self.presets.contains(value) {
                    Text(L10n.resource("\(value) s (current)")).tag(value)
                }
            }
            .labelsHidden()
            .settingsMenuPicker()
            .monitoringControlColumn()
            .accessibilityLabel(L10n.resource("Metrics export interval"))
            .accessibilityValue(L10n.resource("\(value) seconds"))
        }
        .frame(minHeight: SettingsLayout.disclosureRowMinimumHeight)
        .help(L10n.resource("Choose how often LittleSwitch exports metrics."))
    }

    private static func title(for seconds: Int) -> String {
        switch seconds {
        case 60: L10n.string("1 min")
        case 120: L10n.string("2 min")
        case 300: L10n.string("5 min")
        default: L10n.string("\(seconds) s")
        }
    }
}
