import SwiftUI

struct ModelCatalogHeader: View {
    let enabledCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    title
                    count
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    count
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var title: some View {
        SettingsSectionHeader(L10n.resource("Available models"))
            .fixedSize()
    }

    private var count: some View {
        Text(L10n.resource("\(enabledCount) enabled"))
            .font(SettingsLayout.Typography.supporting)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
