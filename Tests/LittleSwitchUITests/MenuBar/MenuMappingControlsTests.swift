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

    @Test("Rapid steps stay optimistic until the latest action completes")
    func optimisticSteppingAndExternalUpdate() async throws {
        var selection: MenuModelOption? = options[0]
        let action = HeldMenuSelection()
        func content() -> MenuModelStepper {
            MenuModelStepper(
                name: "Sonnet", options: options, selection: selection, width: 170, onSelect: action.select)
        }
        let host = MenuControlTestHost(content())
        defer {
            host.close()
            action.releaseAll()
        }
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
        action.releaseAll()
        try await action.waitForCount(3)
        #expect(action.changes == [options[1], options[2], options[0]])
        #expect(selection == options[0])

        selection = options[1]
        host.hosting.rootView = content()
        host.render()
        #expect(host.textContent.contains("Beta"))
        action.hold()
        #expect(try host.element(label: previousLabel("Sonnet")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Alpha"))
        try await action.waitForCount(4)
        #expect(action.changes == [options[1], options[2], options[0], options[0]])
    }

    @Test("A missing selection enters at the requested end of the model list")
    func missingSelection() async throws {
        let action = HeldMenuSelection()
        let host = MenuControlTestHost(
            MenuModelStepper(
                name: L10n.string("Codex"),
                options: options,
                selection: nil,
                width: 170,
                onSelect: action.select
            )
        )
        defer {
            host.close()
            action.releaseAll()
        }
        try await host.activateAccessibility()
        #expect(host.textContent.contains("—"))
        #expect(try host.element(label: previousLabel("Codex")).accessibilityPerformPress())
        host.render()
        #expect(host.textContent.contains("Gamma"))
        try await action.waitForCount(1)
        #expect(action.changes == [options[2]])
    }

    @Test("An empty catalog disables both controls without changing selection")
    func emptyCatalog() async throws {
        var changes: [MenuModelOption?] = []
        let host = MenuControlTestHost(
            MenuModelStepper(
                name: "Opus",
                options: [],
                selection: nil,
                width: 170
            ) { changes.append($0) }
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

@MainActor
private final class HeldMenuSelection {
    private(set) var changes: [MenuModelOption] = []
    private var suspended = true
    private var continuation: CheckedContinuation<Void, Never>?

    func select(_ option: MenuModelOption) async {
        changes.append(option)
        if suspended { await withCheckedContinuation { continuation = $0 } }
    }

    func waitForCount(_ count: Int) async throws {
        _ = try await eventually(description: "\(count) menu actions") {
            await MainActor.run { self.changes.count == count ? true : nil }
        }
    }

    func hold() { suspended = true }

    func releaseAll() {
        suspended = false
        continuation?.resume()
        continuation = nil
    }
}
