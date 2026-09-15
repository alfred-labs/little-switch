import SwiftUI

/// Peer headings always sit above their cards, including routing and app settings.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?
    let content: Content

    init(
        _ title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionContentSpacing) {
            SettingsSectionHeader(title, subtitle: subtitle)
            content
        }
    }
}

struct SettingsSectionHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?

    init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SettingsLayout.Typography.contentSectionTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
