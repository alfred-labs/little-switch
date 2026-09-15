import SwiftUI

/// A quiet native boundary between consumption and the client settings.
struct MenuSettingsSectionHeader: View {
    static let height: CGFloat = 16 + 1 + 8 + 14 + 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().frame(height: 1)
            Text(L10n.resource("Settings"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 14)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
        .frame(width: StatusMenuLayout.width)
    }
}
