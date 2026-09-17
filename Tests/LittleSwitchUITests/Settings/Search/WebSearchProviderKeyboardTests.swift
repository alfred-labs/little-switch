import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Search provider keyboard navigation", .appKitIsolation)
struct WebSearchProviderKeyboardTests {
    @Test("Native arrow commands respect direction, bounds and disabled state", arguments: [false, true])
    func arrowNavigation(rightToLeft: Bool) async throws {
        let skipReason = "SwiftUICore cannot acquire AX focus on GitHub's macOS 27 preview runner."
        if ConditionallyUnavailable.skipOnRunner(skipReason) {
            return
        }
        let forward: UInt16 = rightToLeft ? 123 : 124
        let backward: UInt16 = rightToLeft ? 124 : 123
        let names: [WebSearchProvider: String] = [
            .disabled: L10n.string("None"), .firecrawl: L10n.string("Firecrawl"), .tavily: L10n.string("Tavily"),
            .brave: L10n.string("Brave"), .exa: L10n.string("Exa"),
        ]
        for step in [
            Move(from: .firecrawl, key: forward, to: .tavily),
            Move(from: .tavily, key: forward, to: .brave),
            Move(from: .brave, key: forward, to: .exa),
            Move(from: .exa, key: forward, to: .exa),
            Move(from: .exa, key: backward, to: .brave),
            Move(from: .brave, key: backward, to: .tavily),
            Move(from: .firecrawl, key: backward, to: .disabled),
            Move(from: .disabled, key: backward, to: .disabled),
            Move(from: .firecrawl, key: 126, to: .firecrawl),
            Move(from: .firecrawl, key: 125, to: .firecrawl),
            Move(from: .firecrawl, key: forward, to: .firecrawl, disabled: true),
            Move(from: .firecrawl, key: forward, to: .firecrawl, focused: false),
        ] {
            let selection = SearchProviderSelectionState()
            selection.provider = step.from
            let binding = Binding(get: { selection.provider }, set: { selection.provider = $0 })
            func content(disabled: Bool) -> some View {
                WebSearchProviderPicker(selection: binding)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                    .disabled(disabled)
            }
            let wasActive = NSApplication.shared.isActive
            let host = MenuControlTestHost(
                content(disabled: false),
                width: 600,
                height: 120
            )
            defer {
                host.close()
                #expect(NSApp.isActive == wasActive)
            }
            try await host.activateAccessibility()
            try host.prepareForKeyboardFocus()
            let name = try #require(names[step.from])
            if step.focused {
                try await host.focus(label: name)
            } else {
                try await host.clearFocus()
            }
            if step.disabled {
                // Acquire focus while enabled, then exercise the disabled transition.
                host.hosting.rootView = content(disabled: true)
                host.render()
                try #require(!host.element(label: name).isAccessibilityEnabled())
            }
            host.render()
            #expect(selection.provider == step.from)
            // Each fresh host exercises one native command, including the
            // unfocused case, without stealing the user's application focus.
            host.hosting.keyDown(with: try keyEvent(step.key, window: host.window))
            _ = try await eventually(description: "key \(step.key) selects \(step.to)") {
                await MainActor.run {
                    host.render()
                    return selection.provider == step.to ? true : nil
                }
            }
            #expect(selection.provider == step.to)
        }
    }

    private struct Move {
        let from: WebSearchProvider
        let key: UInt16
        let to: WebSearchProvider
        var disabled = false
        var focused = true
    }

    private func keyEvent(_ key: UInt16, window: NSWindow) throws -> NSEvent {
        let characters: String
        switch key {
        case 123: characters = "\u{F702}"
        case 124: characters = "\u{F703}"
        case 125: characters = "\u{F701}"
        default: characters = "\u{F700}"
        }
        return try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: key
            )
        )
    }
}

@MainActor
@Observable
private final class SearchProviderSelectionState {
    var provider = WebSearchProvider.firecrawl
}
