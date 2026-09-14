import SwiftUI

/// Shared geometry for every destination in the Settings window.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionPageSpacing) {
                content
            }
            .frame(maxWidth: SettingsLayout.contentMaximumWidth)
            .padding(.horizontal, SettingsLayout.sectionPageHorizontalInset)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .font(SettingsLayout.Typography.rowLabel)
    }
}
