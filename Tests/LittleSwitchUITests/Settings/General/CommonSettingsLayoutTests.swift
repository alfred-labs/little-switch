import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Common settings layout")
struct CommonSettingsLayoutTests {
    @Test("Common uses the generic SF Symbol path while product rows stay branded")
    func commonSidebarIcon() throws {
        let source = try source(named: "Settings/Root/SettingsChrome.swift")

        #expect(AppModel.Section.common.systemImage == "slider.horizontal.3")
        #expect(source.contains("if section == .claude"))
        #expect(source.contains("if section == .codex"))
        #expect(source.contains("CodexIcon()"))
        #expect(source.contains("Image(systemName: section.systemImage)"))
    }

    @Test("Launch at login uses a native switch")
    func commonNetworkSwitchStyle() throws {
        let source = try source(named: "Settings/General/CommonSettingsView.swift")

        #expect(source.contains("Toggle("))
        #expect(source.contains(".toggleStyle(.switch)"))
    }

    @Test("Common shows macOS approval action only for the approval state")
    func launchAtLoginApproval() throws {
        let source = try source(named: "Settings/General/CommonSettingsView.swift")

        #expect(source.contains("model.launchAtLoginRequiresApproval"))
        #expect(source.contains("L10n.resource(\"Open Login Items…\")"))
        #expect(source.contains("onOpenLoginItems"))
        #expect(source.contains("model.launchAtLoginAccessibilityValue"))
        #expect(source.contains("model.launchAtLoginAccessibilityHint"))
        #expect(!source.contains("confirmationDialog"))
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
