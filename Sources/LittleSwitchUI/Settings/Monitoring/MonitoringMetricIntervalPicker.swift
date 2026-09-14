import SwiftUI

struct MonitoringMetricIntervalPicker: View {
    @Binding var value: Int

    private static let presets = [5, 10, 15, 30, 60, 120, 300]

    var body: some View {
        LabeledContent("Export every") {
            Picker("Metrics export interval", selection: $value) {
                ForEach(Self.presets, id: \.self) { seconds in
                    Text(Self.title(for: seconds)).tag(seconds)
                }
                // Preserve an existing non-preset interval until a new value is selected.
                if !Self.presets.contains(value) {
                    Text("\(value) s (current)").tag(value)
                }
            }
            .labelsHidden()
            .settingsMenuPicker()
            .monitoringControlColumn()
            .accessibilityLabel("Metrics export interval")
            .accessibilityValue("\(value) seconds")
        }
        .frame(minHeight: SettingsLayout.disclosureRowMinimumHeight)
        .help("Choose how often LittleSwitch exports metrics.")
    }

    private static func title(for seconds: Int) -> String {
        switch seconds {
        case 60: "1 min"
        case 120: "2 min"
        case 300: "5 min"
        default: "\(seconds) s"
        }
    }
}
