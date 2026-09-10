import SwiftUI

/// One native surface per concept; row spacing replaces internal dividers.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
        }
        .font(SettingsLayout.Typography.rowLabel)
        .labeledContentStyle(SettingsValueRowStyle())
    }
}

/// Outside a Form, the automatic style keeps a value beside its label.
/// Cards share a full-width row so every value ends on the same trailing edge.
private struct SettingsValueRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
                .layoutPriority(1)
            Spacer(minLength: 0)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func settingsRow() -> some View {
        frame(minHeight: SettingsLayout.settingsRowMinimumHeight)
    }

    func settingsSupportingText() -> some View {
        font(SettingsLayout.Typography.supporting)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
