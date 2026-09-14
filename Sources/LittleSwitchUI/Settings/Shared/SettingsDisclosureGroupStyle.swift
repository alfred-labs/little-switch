import SwiftUI

struct SettingsDisclosureGroupStyle<Accessory: View>: DisclosureGroupStyle {
    private let accessory: Accessory
    private let accessibilityHint: String
    private let minimumHeaderHeight: CGFloat

    init(
        accessibilityHint: String,
        minimumHeaderHeight: CGFloat = SettingsLayout.disclosureRowMinimumHeight,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.accessibilityHint = accessibilityHint
        self.minimumHeaderHeight = minimumHeaderHeight
        self.accessory = accessory()
    }

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    configuration.isExpanded.toggle()
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                            .font(SettingsLayout.Typography.disclosureIndicator)
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 24)
                            .accessibilityHidden(true)
                        configuration.label
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(accessibilityHint)
                .onKeyPress(.leftArrow) {
                    configuration.isExpanded = false
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    configuration.isExpanded = true
                    return .handled
                }

                accessory
            }
            .frame(minHeight: minimumHeaderHeight)

            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    configuration.content
                }
                .padding(.leading, 20)
                .padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
