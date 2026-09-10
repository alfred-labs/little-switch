import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Status menu appearance")
struct StatusMenuAppearanceTests {
    private final class AppearanceProbe {
        var colorScheme: ColorScheme?
        var contrast: ColorSchemeContrast?
    }

    private struct ProbeView: NSViewRepresentable {
        let probe: AppearanceProbe

        func makeNSView(context: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ view: NSView, context: Context) {
            probe.colorScheme = context.environment.colorScheme
            probe.contrast = context.environment.colorSchemeContrast
        }
    }

    @Test("A retained menu refreshes the full current appearance before rendering")
    func retainedMenuFollowsApplicationAppearance() throws {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        application.appearance = NSAppearance(named: .aqua)

        let probe = AppearanceProbe()
        let hosting = NSHostingView(rootView: ProbeView(probe: probe))
        hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        hosting.setAccessibilityLabel("Hosted menu row")
        hosting.setAccessibilityValue("Preserved value")
        let item = MenuApplyMenuItem(applyAction: MenuApplyAction(isEnabled: true) {})
        item.view = hosting
        let menu = NSMenu()
        // Match the retained menu built when the controller first starts.
        menu.appearance = application.effectiveAppearance
        menu.addItem(item)
        let controller = StatusItemController(
            model: AppModel(),
            onToggleClaude: {},
            onToggleClaudeCode: {},
            onToggleCodex: {},
            onToggleOpenCode: {},
            onMapping: { _, _ in },
            onCodexDefault: { _ in },
            onCodexAutoReview: { _ in },
            onApplyClaude: { _, _ in },
            onApplyCodex: {}
        )
        controller.menuWillOpen(menu)
        let viewer = try #require(hosting.superview)
        let systemContrast = try #require(probe.contrast)
        controller.menuDidClose(menu)

        // ColorSchemeContrast follows the user's accessibility setting;
        // Apple documents that apps cannot override it with NSAppearance.
        let appearances: [(NSAppearance.Name, ColorScheme)] = [
            (.aqua, .light),
            (.darkAqua, .dark),
            (.aqua, .light),
        ]
        let candidates: [NSAppearance.Name] = [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]
        for (name, colorScheme) in appearances {
            application.appearance = NSAppearance(named: name)

            controller.menuWillOpen(menu)

            #expect(menu.appearance === application.effectiveAppearance)
            // AppKit composes the menu's effective appearance, so the row
            // inherits equivalent attributes without sharing the app object.
            #expect(
                hosting.appearance?.bestMatch(from: candidates)
                    == menu.effectiveAppearance.bestMatch(from: candidates)
            )
            #expect(hosting.appearance?.allowsVibrancy == menu.effectiveAppearance.allowsVibrancy)
            #expect(probe.colorScheme == colorScheme)
            #expect(probe.contrast == systemContrast)
            #expect(hosting.accessibilityLabel() == "Hosted menu row")
            #expect(hosting.accessibilityValue() as? String == "Preserved value")
            #expect(hosting.superview === viewer)
            #expect(item.keyEquivalent == "\r")

            controller.menuDidClose(menu)

            #expect(item.keyEquivalent.isEmpty)
        }
    }
}
