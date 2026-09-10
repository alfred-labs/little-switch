import AppKit
import SwiftUI

@MainActor
enum LittleSwitchAppearance {
    static func apply(to target: any NSAppearanceCustomization) {
        target.appearance = nil
    }
}

@MainActor
enum SettingsWindowChrome {
    static func apply(to window: NSWindow) {
        window.styleMask.formUnion([.fullSizeContentView, .unifiedTitleAndToolbar])

        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "LittleSwitchSettingsToolbar")
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
        }

        window.title = "LittleSwitch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.backgroundColor = SettingsLayout.Palette.detailBackground
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 0
        window.contentView?.layer?.masksToBounds = false
        window.contentView?.layer?.borderColor = nil
    }
}

struct SettingsSidebarRow: View {
    let section: AppModel.Section

    var body: some View {
        HStack(spacing: 9) {
            if section == .claude {
                ClaudeIcon()
                    .frame(width: 16, height: 16)
                    .frame(
                        width: SettingsLayout.sidebarIconSize,
                        height: SettingsLayout.sidebarIconSize
                    )
            } else if section == .openCode {
                OpenCodeIcon()
                    .frame(width: 14, height: 14)
                    .frame(
                        width: SettingsLayout.sidebarIconSize,
                        height: SettingsLayout.sidebarIconSize
                    )
            } else if section == .codex {
                CodexIcon()
                    .frame(width: 16, height: 16)
                    .frame(
                        width: SettingsLayout.sidebarIconSize,
                        height: SettingsLayout.sidebarIconSize
                    )
            } else {
                Image(systemName: section.systemImage)
                    .symbolVariant(.none)
                    .symbolRenderingMode(.monochrome)
                    .font(SettingsLayout.Typography.sidebarIcon)
                    .frame(width: SettingsLayout.sidebarIconSize)
            }
            Text(section.rawValue)
                .font(SettingsLayout.Typography.sidebarLabel)
        }
        .frame(minHeight: SettingsLayout.sidebarRowMinimumHeight, alignment: .leading)
    }
}

struct SettingsSidebarIdentity: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("LittleSwitch")
                    .font(SettingsLayout.Typography.sectionTitle)
                Text("Settings")
                    .font(SettingsLayout.Typography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The one way the window says a section holds changes that are not live yet.
/// Every pane with a draft shows this, in the same words, in the same place.
struct SettingsPendingNotice: View {
    var body: some View {
        Label("Changes are ready to apply.", systemImage: "checkmark.circle")
            .labelStyle(.titleAndIcon)
            .font(SettingsLayout.Typography.toolbarLabel)
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
