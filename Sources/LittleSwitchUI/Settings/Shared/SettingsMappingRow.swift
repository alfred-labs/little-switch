import SwiftUI

struct SettingsMappingRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GridRow {
            Text(title)
                .font(SettingsLayout.Typography.rowLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content
                .labelsHidden()
                .settingsMenuPicker(width: SettingsLayout.mappingControlWidth)
        }
        .frame(minHeight: SettingsLayout.mappingRowMinimumHeight)
    }
}
