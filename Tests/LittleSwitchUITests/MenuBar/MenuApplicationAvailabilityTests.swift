import AppKit
import LittleSwitchCommon
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Menu application availability", .appKitIsolation)
struct MenuApplicationAvailabilityTests {
    @Test("Only the app icons launch, independently from connection switches")
    func launchActions() async throws {
        let model = AppModel()
        model.desktopApplications = .init(claude: .available, codex: .available, openCode: .available)
        var opened: [DesktopApplication] = []
        var connectionActions = 0
        let host = MenuControlTestHost(
            MenuStatusView(
                model: model,
                onToggleClaude: { connectionActions += 1 },
                onToggleClaudeCode: {},
                onToggleCodex: { connectionActions += 1 },
                onToggleOpenCode: { connectionActions += 1 },
                onOpenApplication: { opened.append($0) }
            ),
            height: StatusMenuLayout.applicationBlockHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()
        for application in DesktopApplication.allCases {
            let button = try host.element(label: L10n.string("Open \(application.displayName)"))
            #expect(button.accessibilityRole() == .button)
            #expect(button.isAccessibilityEnabled())
            #expect(button.accessibilityPerformPress())
        }
        #expect(opened == [.claude, .codex, .openCode])
        #expect(connectionActions == 0)
        #expect(!model.connected && !model.codexConnected && !model.openCodeSwitchOn)
        #expect(
            !host.accessibilityElements.contains {
                $0.accessibilityRole() == .button && $0.accessibilityLabel() == L10n.string("Codex")
            })
        model.launchingApplications = [.codex]
        host.render()
        #expect(
            try !host.element(label: L10n.string("Open \(DesktopApplication.codex.displayName)"))
                .isAccessibilityEnabled())
        #expect(
            try host.element(label: L10n.string("\(DesktopApplication.codex.displayName) connection"))
                .isAccessibilityEnabled())
        model.isBusy = true
        host.render()
        for application in DesktopApplication.allCases {
            #expect(try !host.element(label: L10n.string("Open \(application.displayName)")).isAccessibilityEnabled())
        }
    }

    @Test("Managed Claude disables its icon and switch without disabling other clients")
    func managedClaude() async throws {
        let model = AppModel()
        model.desktopApplications = .init(claude: .organizationManaged, codex: .available, openCode: .available)
        let host = MenuControlTestHost(
            MenuStatusView(
                model: model, onToggleClaude: {}, onToggleClaudeCode: {}, onToggleCodex: {}, onToggleOpenCode: {}),
            height: StatusMenuLayout.applicationBlockHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(
            try !host.element(label: L10n.string("Open \(DesktopApplication.claude.displayName)"))
                .isAccessibilityEnabled())
        #expect(
            try !host.element(label: L10n.string("\(DesktopApplication.claude.displayName) connection"))
                .isAccessibilityEnabled())
        #expect(
            try host.element(label: L10n.string("Open \(DesktopApplication.codex.displayName)"))
                .isAccessibilityEnabled())
        #expect(host.textContent.contains(L10n.string("Organization managed")))
        #expect(
            model.claudePrimaryActionAccessibilityHint
                == DesktopApplicationLaunchError.organizationManaged.errorDescription)
    }

    @Test("Missing desktop apps disable their connection switches")
    func missingApplications() async throws {
        let model = AppModel()
        let host = MenuControlTestHost(
            MenuStatusView(
                model: model,
                onToggleClaude: {},
                onToggleClaudeCode: {},
                onToggleCodex: {},
                onToggleOpenCode: {}
            ),
            height: StatusMenuLayout.applicationBlockHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()

        for name in ["Claude Desktop", "Codex", "OpenCode"] {
            let toggle = try host.element(label: L10n.string("\(name) connection"))
            #expect(!toggle.isAccessibilityEnabled())
        }
        let terminal = try host.element(label: L10n.string("\(L10n.string("Claude Code")) connection"))
        #expect(terminal.isAccessibilityEnabled())
    }
}
