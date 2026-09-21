import AppKit
import SwiftUI

enum SettingsLayout {
    static let windowWidth: CGFloat = 1_200
    static let windowHeight: CGFloat = 840
    static let minimumWindowWidth: CGFloat = windowWidth
    static let minimumWindowHeight: CGFloat = windowHeight
    static let sidebarMinimumWidth: CGFloat = 160
    static let sidebarIdealWidth: CGFloat = 180
    static let sidebarMaximumWidth: CGFloat = 184
    static let sidebarToggleSize: CGFloat = 28
    static let sidebarToggleToolbarLeadingPadding: CGFloat = 36
    static let titlebarHeight: CGFloat = 52
    static let minimumContentHeight: CGFloat = minimumWindowHeight - titlebarHeight
    static let sidebarRowMinimumHeight: CGFloat = 30
    static let sidebarRowAdditionalLeadingPadding: CGFloat = 4
    static let sidebarLabelFontSize: CGFloat = 13.5
    static let sidebarIconSize: CGFloat = 17
    static let contentMaximumWidth: CGFloat = 640
    static let mappingControlWidth: CGFloat = 280
    static let mappingRowMinimumHeight: CGFloat = 38
    static let sectionPageHorizontalInset: CGFloat = 40
    static let sectionPageSpacing: CGFloat = 28
    static let sectionContentSpacing: CGFloat = 12
    static let settingsRowMinimumHeight: CGFloat = 38
    static let generalControlWidth: CGFloat = 160
    static let disclosureRowMinimumHeight: CGFloat = 34
    static let disclosureDetailRowMinimumHeight: CGFloat = 24
    static let catalogModelRowMinimumHeight: CGFloat = 30
    static let monitoringControlWidth: CGFloat = 110
    static let menuPickerControlSize: ControlSize = .regular

    enum ProviderEditor {
        static let minimumWidth: CGFloat = 720
        static let minimumHeight: CGFloat = 660
        static let idealWidth: CGFloat = 800
        static let idealHeight: CGFloat = 760
        static let controlWidth: CGFloat = 216
        static let contextCapacityWidth: CGFloat = 126
        static let contextClaudeWidth: CGFloat = 126
    }

    enum Palette {
        static let sidebarBackground = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(srgbRed: 33 / 255, green: 33 / 255, blue: 33 / 255, alpha: 1)
            }
            return .controlBackgroundColor
        }

        static let detailBackground = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
            }
            return .textBackgroundColor
        }
    }

    enum Toolbar {
        static let actionSpacing: CGFloat = 12
        static let trailingInset: CGFloat = 16
        static let buttonHorizontalInset: CGFloat = 8
        static let buttonHeight: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 10
        static let buttonLabelSpacing: CGFloat = 4
        static let buttonIconSize: CGFloat = 16
        static let buttonHoverOpacity: Double = 0.08
        static let buttonPressedOpacity: Double = 0.12
        static let buttonDisabledOpacity: Double = 0.4
    }

    enum SearchProvider {
        static let tileSize: CGFloat = 50
        static let logoSize: CGFloat = 24
        static let choiceWidth: CGFloat = 96
        static let choiceSpacing: CGFloat = 24
        static let cornerRadius: CGFloat = 10
        static let labelSpacing: CGFloat = 8
        static let verticalInset: CGFloat = 8
        static let checkmarkInset: CGFloat = 5
    }

    /// One typographic scale for the whole window.
    ///
    /// Body text uses Codex Desktop's CSS weight 430. Headings use 500.
    /// Compact toolbar actions and status share a 13-point regular font.
    /// Set the system font's public variation axis to retain its optical sizing.
    enum Typography {
        static let textWeight = 430
        static let rowLabel = textFont(size: 13)
        static let toolbarLabel = Font.system(size: 13, weight: .regular)
        static let toolbarIcon = Font.system(size: 13, weight: .light)
        static let selectionCheckmark = Font.system(size: 9, weight: .medium)
        static let disclosureTitle = Font.system(size: 14, weight: .medium)
        static let disclosureIndicator = Font.system(size: 11, weight: .light)
        static let contentSectionTitle = Font.system(size: 17, weight: .medium)
        static let supporting = textFont(size: 11.5)
        static let sectionTitle = Font.system(size: 13, weight: .medium)
        static let monospacedValue = textFont(size: 11.5).monospaced()
        static let sidebarLabel = textFont(size: sidebarLabelFontSize)
        static let sidebarIcon = Font.system(size: sidebarLabelFontSize, weight: .light)
        static let sidebarToggleIcon = Font.system(size: 15, weight: .light)

        private static func textFont(size: CGFloat) -> Font {
            let systemFont = NSFont.systemFont(ofSize: size)
            let descriptor = systemFont.fontDescriptor.addingAttributes([
                .variation: [0x7767_6874: textWeight]  // OpenType "wght" axis, in CSS units.
            ])
            return Font(NSFont(descriptor: descriptor, size: size) ?? systemFont)
        }
    }
}

extension View {
    func settingsMenuPicker(width: CGFloat? = nil) -> some View {
        pickerStyle(.menu)
            .controlSize(SettingsLayout.menuPickerControlSize)
            .modifier(SettingsMenuPickerWidth(width: width))
    }

    @ViewBuilder
    func monitoringControlColumn() -> some View {
        if #available(macOS 26.0, *) {
            buttonSizing(.flexible)
                .frame(width: SettingsLayout.monitoringControlWidth)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            frame(width: SettingsLayout.monitoringControlWidth)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct SettingsMenuPickerWidth: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), let width {
            content
                .buttonSizing(.flexible)
                .frame(width: width, alignment: .trailing)
        } else {
            content.frame(width: width, alignment: .trailing)
        }
    }
}
