import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Menu mapping controls")
struct MenuMappingControlsTests {
    private let options = [
        MenuModelOption(id: "alpha", label: "Alpha", mapping: nil),
        MenuModelOption(id: "beta", label: "Beta", mapping: nil),
        MenuModelOption(id: "gamma", label: "Gamma", mapping: nil),
    ]

    @Test("Rapid steps stay optimistic until the external selection changes")
    func optimisticSteppingAndExternalUpdate() async throws {
        var selection: MenuModelOption? = options[0]
        var changes: [MenuModelOption?] = []
        let binding = Binding(get: { selection }, set: { changes.append($0) })
        func content() -> MenuModelStepper {
            MenuModelStepper(name: "Sonnet", options: options, selection: binding, width: 170)
        }
        let host = MenuControlTestHost(content())
        defer { host.close() }
        try await host.activateAccessibility()

        #expect(host.textContent.contains("Alpha"))
        #expect(try host.element(label: nextLabel("Sonnet")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Beta"))
        #expect(try host.element(label: nextLabel("Sonnet")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Gamma"))
        #expect(try host.element(label: nextLabel("Sonnet")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Alpha"))
        #expect(changes == [options[1], options[2], options[0]])
        #expect(selection == options[0])

        selection = options[1]
        host.hosting.rootView = content()
        host.render()
        #expect(host.textContent.contains("Beta"))
        #expect(try host.element(label: previousLabel("Sonnet")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Alpha"))
        #expect(changes == [options[1], options[2], options[0], options[0]])
    }

    @Test("A missing selection enters at the requested end of the model list")
    func missingSelection() async throws {
        var changes: [MenuModelOption?] = []
        let host = MenuControlTestHost(
            MenuModelStepper(
                name: L10n.string("Codex"),
                options: options,
                selection: Binding(get: { nil }, set: { changes.append($0) }),
                width: 170
            )
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(host.textContent.contains("—"))
        #expect(try host.element(label: previousLabel("Codex")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Gamma"))
        #expect(changes == [options[2]])
    }

    @Test("An empty catalog disables both controls without changing selection")
    func emptyCatalog() async throws {
        var changes: [MenuModelOption?] = []
        let host = MenuControlTestHost(
            MenuModelStepper(
                name: "Opus",
                options: [],
                selection: Binding(get: { nil }, set: { changes.append($0) }),
                width: 170
            )
        )
        defer { host.close() }
        try await host.activateAccessibility()
        for label in [previousLabel("Opus"), nextLabel("Opus")] {
            let button = try host.element(label: label)
            #expect(!button.isAccessibilityEnabled())
            _ = button.accessibilityPerformPress()
        }
        #expect(changes.isEmpty)
    }

    @Test("Loading remains readable and its mapping arrow stays decorative")
    func loadingPlaceholder() async throws {
        let host = MenuControlTestHost(
            HStack {
                MenuMappingArrow()
                MenuModelLoadingPlaceholder()
            }
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(host.textContent.contains(L10n.string("Loading models…")))
        #expect(!host.accessibilityElements.contains { $0.accessibilityRole() == .button })
        #expect(!host.accessibilityElements.contains { $0.accessibilityRole() == .image })
    }

    private func nextLabel(_ name: String) -> String {
        L10n.string("Next model for \(name)")
    }

    private func previousLabel(_ name: String) -> String {
        L10n.string("Previous model for \(name)")
    }
}
