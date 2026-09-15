import SwiftUI

struct SettingsConnectionStatus: View {
    let connected: Bool
    var title: String?

    var body: some View {
        statusText
            .font(SettingsLayout.Typography.toolbarLabel)
            .foregroundStyle(connected ? Color.green : Color.secondary)
            .fixedSize()
    }

    @ViewBuilder
    private var statusText: some View {
        if let title {
            Text(title)
        } else if connected {
            Text(L10n.resource("Connected"))
        } else {
            Text(L10n.resource("Not connected"))
        }
    }
}
