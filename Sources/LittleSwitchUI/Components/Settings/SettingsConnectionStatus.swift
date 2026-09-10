import SwiftUI

struct SettingsConnectionStatus: View {
    let connected: Bool
    var title: String?

    var body: some View {
        Text(title ?? (connected ? "Connected" : "Not connected"))
            .font(SettingsLayout.Typography.toolbarLabel)
            .foregroundStyle(connected ? Color.green : Color.secondary)
            .fixedSize()
    }
}
