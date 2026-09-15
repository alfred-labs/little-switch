import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Status menu switches")
struct MenuStatusSwitchTests {
    @Test("Connected switches keep their accent in inactive menus", arguments: [ColorScheme.light, .dark])
    func inactiveAppearance(colorScheme: ColorScheme) async throws {
        let model = connectedModel()
        let host = MenuControlTestHost(
            menu(model: model)
                .tint(.blue)
                .environment(\.colorScheme, colorScheme)
                .environment(\.appearsActive, false)
                .transaction { $0.disablesAnimations = true },
            width: StatusMenuLayout.width,
            height: StatusMenuLayout.applicationBlockHeight
        )
        defer { host.close() }
        host.hosting.appearance = try #require(NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
        try await host.activateAccessibility()
        let connectedPixels = try switchAccentPixels(in: host.hosting)
        #expect(connectedPixels.count == 4)
        for count in connectedPixels {
            #expect(count > 10, "An ON switch has no accent in the inactive \(colorScheme) menu")
        }

        host.hosting.removeFromSuperview()
        StatusMenuHostedViewWarmup.warm(view: host.hosting)
        #expect(host.hosting.superview == nil)
        host.window.contentView = host.hosting
        host.render()
        for count in try switchAccentPixels(in: host.hosting) {
            #expect(count > 10, "An ON switch lost its accent after menu reattachment")
        }

        model.apply(CoordinatorSnapshot(configuration: AppConfiguration()))
        host.render()
        #expect(try switchAccentPixels(in: host.hosting) == [0, 0, 0, 0])
    }

    @Test("Connection toggles retain names, values, actions and busy protection")
    func accessibilityAndActions() async throws {
        let model = connectedModel()
        var actions: [String] = []
        let host = MenuControlTestHost(
            MenuStatusView(
                model: model,
                onToggleClaude: { actions.append(L10n.string("Claude Desktop")) },
                onToggleClaudeCode: { actions.append(L10n.string("Claude Code")) },
                onToggleCodex: { actions.append(L10n.string("Codex")) },
                onToggleOpenCode: { actions.append(L10n.string("OpenCode")) }
            )
            .environment(\.appearsActive, false),
            width: StatusMenuLayout.width,
            height: StatusMenuLayout.applicationBlockHeight
        )
        defer { host.close() }
        try await host.activateAccessibility()
        let names = [
            L10n.string("Claude Desktop"), L10n.string("Claude Code"), L10n.string("Codex"), L10n.string("OpenCode"),
        ]
        for name in names {
            let toggle = try host.element(label: L10n.string("\(name) connection"))
            #expect(toggle.accessibilityRole() == .checkBox)
            #expect(toggle.accessibilityValue() as? Int == 1)
            #expect(toggle.isAccessibilityEnabled())
            #expect(toggle.accessibilityPerformPress())
        }
        #expect(actions == names)

        model.isBusy = true
        host.render()
        for name in names {
            #expect(try !host.element(label: L10n.string("\(name) connection")).isAccessibilityEnabled())
        }
        model.apply(CoordinatorSnapshot(configuration: AppConfiguration()))
        host.render()
        for name in names {
            #expect(
                try host.element(label: L10n.string("\(name) connection")).accessibilityValue() as? Int == 0
            )
        }
    }

    private func connectedModel() -> AppModel {
        var configuration = AppConfiguration(connected: true)
        configuration.codex.connected = true
        return AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                claudeCodeStatus: .connected,
                openCodeStatus: .connected
            )
        )
    }

    private func menu(model: AppModel) -> some View {
        MenuStatusView(
            model: model,
            onToggleClaude: {},
            onToggleClaudeCode: {},
            onToggleCodex: {},
            onToggleOpenCode: {}
        )
    }

    private func switchAccentPixels(in hosting: NSView) throws -> [Int] {
        let rectangle = NSRect(
            x: StatusMenuLayout.width - StatusMenuLayout.horizontalPadding - 40,
            y: 0,
            width: 40,
            height: StatusMenuLayout.applicationBlockHeight
        )
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: rectangle))
        hosting.cacheDisplay(in: rectangle, to: bitmap)
        var counts = [Int](repeating: 0, count: 4)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let blueOverRed = color.blueComponent - color.redComponent
                let blueOverGreen = color.blueComponent - color.greenComponent
                if color.alphaComponent > 0.5 && blueOverRed > 0.25 && blueOverGreen > 0.1 {
                    counts[min(3, y * 4 / bitmap.pixelsHigh)] += 1
                }
            }
        }
        return counts
    }
}
