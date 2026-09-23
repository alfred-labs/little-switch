import SwiftUI

/// Keep the page's state and commit action together. A stable native group
/// label prevents AppKit from caching the initial status as its accessible name.
struct SettingsToolbarActions<Content: View>: ToolbarContent {
    @ViewBuilder var content: Content

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                actions
            } label: {
                Text(L10n.resource("Settings actions"))
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { Spacer() }
            ToolbarItemGroup(placement: .primaryAction) {
                actions
            } label: {
                Text(L10n.resource("Settings actions"))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: SettingsLayout.Toolbar.actionSpacing) { content }
            .font(SettingsLayout.Typography.toolbarLabel)
            .labelStyle(.titleAndIcon)
            .buttonStyle(SettingsToolbarButtonStyle())
            .controlSize(.regular)
            .fixedSize()
            .padding(.trailing, SettingsLayout.Toolbar.trailingInset)
            // The native AX bridge otherwise applies the toolbar item's inferred
            // label to its children, even when their direct AX selectors differ.
            .accessibilityElement(children: .contain)
    }
}

/// Match the quiet, rounded hover treatment of Codex Desktop's toolbar actions.
private struct SettingsToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsToolbarButtonBody(configuration: configuration)
    }
}

private struct SettingsToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(SettingsToolbarLabelStyle())
            .font(SettingsLayout.Typography.toolbarLabel)
            .foregroundStyle(.secondary)
            .padding(.horizontal, SettingsLayout.Toolbar.buttonHorizontalInset)
            .frame(minHeight: SettingsLayout.Toolbar.buttonHeight)
            .background(
                (colorScheme == .dark ? Color.white : Color.black).opacity(backgroundOpacity),
                in: shape
            )
            .contentShape(shape)
            .opacity(isEnabled ? 1 : SettingsLayout.Toolbar.buttonDisabledOpacity)
            .onHover { isHovered = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsLayout.Toolbar.buttonCornerRadius, style: .continuous)
    }

    private var backgroundOpacity: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return SettingsLayout.Toolbar.buttonPressedOpacity }
        return isHovered ? SettingsLayout.Toolbar.buttonHoverOpacity : 0
    }
}

private struct SettingsToolbarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: SettingsLayout.Toolbar.buttonLabelSpacing) {
            configuration.icon
                .font(SettingsLayout.Typography.toolbarIcon)
                .frame(
                    width: SettingsLayout.Toolbar.buttonIconSize,
                    height: SettingsLayout.Toolbar.buttonIconSize
                )
            configuration.title
        }
    }
}

extension View {
    func settingsWindowTitle(_ title: String) -> some View {
        modifier(SettingsWindowTitle(title: title))
    }
}

private struct SettingsWindowTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar(removing: nativeTitleItem)
    }

    private var nativeTitleItem: ToolbarDefaultItemKind? {
        if #available(macOS 15.0, *) { return .title }
        // SettingsWindowChrome hides the native title on macOS 14.
        return nil
    }
}
