import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@Suite("Settings layout")
struct SettingsLayoutTests {
    @Test("Settings keep a compact product layout while the window resizes")
    func compactMetrics() {
        #expect(SettingsLayout.windowWidth == 1_200)
        #expect(SettingsLayout.windowHeight == 840)
        #expect(SettingsLayout.minimumWindowWidth == 1_200)
        #expect(SettingsLayout.minimumWindowHeight == 840)
        #expect(SettingsLayout.sidebarMinimumWidth == 160)
        #expect(SettingsLayout.sidebarIdealWidth == 180)
        #expect(SettingsLayout.sidebarMaximumWidth == 184)
        #expect(SettingsLayout.sidebarToggleSize == 28)
        #expect(SettingsLayout.titlebarHeight == 52)
        #expect(SettingsLayout.sidebarRowMinimumHeight == 30)
        #expect(SettingsLayout.sidebarRowAdditionalLeadingPadding == 4)
        #expect(SettingsLayout.sidebarLabelFontSize == 13.5)
        #expect(SettingsLayout.sidebarIconSize == 17)
        #expect(SettingsLayout.contentMaximumWidth == 640)
        #expect(SettingsLayout.mappingControlWidth == 280)
        #expect(SettingsLayout.mappingRowMinimumHeight == 38)
        #expect(SettingsLayout.sectionContentSpacing == 12)
        #expect(SettingsLayout.settingsRowMinimumHeight == 38)
        #expect(SettingsLayout.menuPickerControlSize == .regular)
    }

    @Test("Settings use one flat integrated sidebar and one native top toggle")
    func flatIntegratedSidebar() throws {
        let settingsSource = try source(named: "Application/Settings/SettingsView.swift")
        let splitSource = try source(named: "Application/Settings/SettingsSplitView.swift")

        #expect(!settingsSource.contains("NavigationSplitView"))
        #expect(settingsSource.contains("SettingsSplitView("))
        #expect(splitSource.contains("HStack(spacing: 0)"))
        #expect(splitSource.contains("Color(nsColor: SettingsLayout.Palette.sidebarBackground)"))
        #expect(splitSource.contains("Color(nsColor: SettingsLayout.Palette.detailBackground)"))
        #expect(splitSource.contains("ToolbarItem(placement: .navigation)"))
        #expect(splitSource.contains(".overlay(alignment: .topLeading)"))
        #expect(splitSource.contains("GeometryReader"))
        #expect(splitSource.contains("geometry.size.height + SettingsLayout.titlebarHeight"))
        #expect(splitSource.contains(".buttonStyle(.borderless)"))
        #expect(splitSource.contains("Image(systemName: \"sidebar.left\")"))
        #expect(splitSource.contains("\"Hide sidebar\""))
        #expect(splitSource.contains("\"Show sidebar\""))
    }

    @Test("Settings window uses integrated public AppKit titlebar chrome")
    func integratedWindowChrome() throws {
        let source = try source(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let appearance = try #require(
            source.range(of: "LittleSwitchAppearance.apply(to: NSApp)")
        )
        let monitor = try #require(source.range(of: "signalMonitor.start"))

        #expect(source.contains("SettingsWindowChrome.apply(to: window)"))
        #expect(appearance.lowerBound < monitor.lowerBound)
    }

    @MainActor
    @Test("LittleSwitch follows the system appearance")
    func systemApplicationAppearance() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        LittleSwitchAppearance.apply(to: window)

        #expect(window.appearance == nil)
    }

    @MainActor
    @Test("Settings window chrome uses one lightweight unified surface")
    func lightweightUnifiedWindowChrome() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        SettingsWindowChrome.apply(to: window)

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.styleMask.contains(.unifiedTitleAndToolbar))
        #expect(window.title == "LittleSwitch")
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none)
        #expect(window.toolbarStyle == .unified)
        #expect(window.appearance == nil)
        #expect(window.toolbar != nil)
        #expect(window.toolbar?.showsBaselineSeparator == false)
        #expect(window.contentView?.layer?.cornerRadius == 0)
        #expect(window.contentView?.layer?.borderColor == nil)
    }

    @Test("Settings sidebar is flat and compact")
    func flatCompactSidebar() throws {
        let viewsSource = try source(named: "Application/Settings/SettingsView.swift")
        let chromeSource = try source(named: "Application/Settings/SettingsChrome.swift")

        #expect(viewsSource.contains(".listStyle(.sidebar)"))
        #expect(!viewsSource.contains(".listStyle(.plain)"))
        #expect(viewsSource.contains(".scrollContentBackground(.hidden)"))
        #expect(viewsSource.contains("SettingsLayout.sidebarRowMinimumHeight"))
        #expect(viewsSource.contains("SettingsLayout.sidebarRowAdditionalLeadingPadding"))
        #expect(chromeSource.contains("SettingsLayout.Typography.sidebarLabel"))
        #expect(!chromeSource.contains("sidebarLabelSelected"))
        #expect(chromeSource.contains("SettingsLayout.sidebarIconSize"))
        #expect(viewsSource.contains(".listRowSeparator(.hidden)"))
        #expect(!viewsSource.contains(".listSectionSeparator"))
        #expect(!viewsSource.contains("Section(group.title)"))
    }

    @Test("Claude routing rows keep airy arrow mappings without separators")
    func airyClaudeRoutingRows() throws {
        let pageSource = try source(named: "Features/Clients/Claude/ClaudeSettingsView.swift")
        let source = try source(named: "Components/Settings/SettingsMappingRow.swift")

        #expect(pageSource.contains("SettingsMappingRow(route.displayName)"))
        #expect(source.contains("SettingsLayout.mappingRowMinimumHeight"))
        #expect(source.contains("Image(systemName: \"arrow.right\")"))
        #expect(!source.contains("SettingsRowDivider()"))
        #expect(source.contains("SettingsLayout.Typography.rowLabel"))
        #expect(source.contains(".settingsMenuPicker(width: SettingsLayout.mappingControlWidth)"))
    }

}

extension SettingsLayoutTests {

    @Test("Claude Code integrates Anthropic context variants in one aligned default menu")
    func claudeCodeDefaultModelVariants() throws {
        let pageSource = try source(named: "Features/Clients/ClaudeCode/ClaudeCodeSettingsView.swift")

        #expect(pageSource.contains("model.claudeCodeDefaultModelOptions"))
        #expect(pageSource.contains("model.claudeCodeDefaultModelSelection"))
        #expect(pageSource.contains("option.routeID, option.contextMode"))
        #expect(!pageSource.contains("Text(\"Context window\")"))
        #expect(!pageSource.contains(".pickerStyle(.segmented)"))
        #expect(!pageSource.contains("onContextMode"))
        #expect(
            pageSource.components(
                separatedBy: ".settingsMenuPicker(width: SettingsLayout.mappingControlWidth)"
            ).count == 2
        )
        #expect(pageSource.contains("LabeledContent(\"Default model\")"))
    }

    @Test("Claude exposes one shared Apply action without connection badges")
    func claudeSingleApplyAction() throws {
        let pageSource = try source(named: "Features/Clients/ClaudeCode/ClaudeCodeSettingsView.swift")
        let claudeSource = try source(named: "Features/Clients/Claude/ClaudeSettingsView.swift")

        #expect(claudeSource.contains("\"Apply\""))
        #expect(claudeSource.contains("applyAllClaudeSettings()"))
        #expect(claudeSource.contains("model.claudePrimaryAction"))
        #expect(claudeSource.contains("model.claudeCodePrimaryAction"))
        #expect(!pageSource.contains("Button("))
        #expect(!pageSource.contains("statusBadge"))
        #expect(!pageSource.contains("Disconnected"))
    }

    @Test("Claude navigation uses the Claude color mark")
    func claudeNavigationIcon() throws {
        let chromeSource = try source(named: "Application/Settings/SettingsChrome.swift")
        let iconSource = try source(named: "Components/BrandIcons/ClaudeIcon.swift")

        #expect(chromeSource.contains("section == .claude"))
        #expect(chromeSource.contains("ClaudeIcon()"))
        #expect(iconSource.contains("struct ClaudeIcon: View"))
    }

    private func source(named filename: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/\(filename)"
            ),
            encoding: .utf8
        )
    }
}
