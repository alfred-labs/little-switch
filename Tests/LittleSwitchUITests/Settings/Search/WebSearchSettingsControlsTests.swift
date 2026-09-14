import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchSearch
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Web search settings controls", .serialized)
struct WebSearchSettingsControlsTests {
    init() { _ = NSApplication.shared }

    @Test("Saved-key guidance is the secure field's placeholder")
    func credentialPlaceholder() throws {
        let hosting = hostPage()
        let field = try #require(descendant(NSSecureTextField.self, in: hosting))

        #expect(field.placeholderString == "Leave blank to keep the saved key")
        #expect(field.stringValue.isEmpty)
        #expect(field.alignment == .natural)
    }

    @Test("Search services expose five named native buttons and one accessible selection")
    func providerChoices() async throws {
        let host = MenuControlTestHost(WebSearchProviderPicker(selection: .constant(.tavily)), width: 600, height: 120)
        defer { host.close() }
        try await host.activateAccessibility()

        let group = try host.element(label: "Search provider")
        #expect(group.accessibilityRole() == .group)
        let names = ["None", "Firecrawl", "Tavily", "Brave", "Exa"]
        let buttons = host.accessibilityElements.filter { $0.accessibilityRole() == .button }
        #expect(Set(buttons.compactMap { $0.accessibilityLabel() }) == Set(names))
        #expect(buttons.count == 5)
        for name in names {
            let button = try host.element(label: name)
            #expect(button.isAccessibilityEnabled())
            #expect(button.object.isAccessibilitySelected?() == (name == "Tavily"))
        }
    }

    @Test("A native provider selection clears the previous key and clamps limits; reselecting preserves typing")
    func providerSelectionUpdatesDraft() async throws {
        let state = WebSearchControlDraft(
            configuration: WebSearchConfiguration(provider: .firecrawl, resultsLimit: 80, maximumUses: 3)
        )
        state.draft.credential = "previous-provider-test-key"
        let host = MenuControlTestHost(
            WebSearchProviderPicker(
                selection: Binding(get: { state.draft.provider }, set: { state.draft.select(provider: $0) })
            ),
            width: 600,
            height: 120
        )
        defer { host.close() }
        try await host.activateAccessibility()
        #expect(try host.element(label: "Tavily").accessibilityPerformPress())
        try await expectSelection("Tavily", in: host)

        #expect(
            state.draft.input
                == WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .tavily, resultsLimit: 20, maximumUses: 3),
                    credential: nil
                ))
        state.draft.credential = "current-provider-test-key"
        host.render()
        #expect(try host.element(label: "Tavily").accessibilityPerformPress())
        try await expectSelection("Tavily", in: host)
        #expect(state.draft.credential == "current-provider-test-key")

        host.render()
        #expect(try host.element(label: "None").accessibilityPerformPress())
        try await expectSelection("None", in: host)
        #expect(
            state.draft.input
                == WebSearchInput(
                    configuration: WebSearchConfiguration(provider: .disabled, resultsLimit: 20, maximumUses: 3),
                    credential: nil
                ))
    }

    private func expectSelection<Content: View>(_ name: String, in host: MenuControlTestHost<Content>) async throws {
        _ = try await eventually(description: "only \(name) is selected") {
            await MainActor.run {
                host.render()
                let selected = host.accessibilityElements.filter {
                    $0.accessibilityRole() == .button && $0.object.isAccessibilitySelected?() == true
                }
                return selected.map { $0.accessibilityLabel() } == [name] ? true : nil
            }
        }
    }

    @Test("Provider buttons retain their intrinsic size when the parent does not propose a width")
    func intrinsicSize() async throws {
        let host = MenuControlTestHost(
            WebSearchProviderPicker(selection: .constant(.disabled)).fixedSize(), width: 600, height: 120
        )
        defer { host.close() }
        try await host.activateAccessibility()
        let frames = try ["None", "Firecrawl", "Tavily", "Brave", "Exa"].map { name in
            let control = try host.element(label: name)
            return try #require(control.object.accessibilityFrame?())
        }
        #expect(frames.allSatisfy { $0.width > 0 && $0.height >= SettingsLayout.SearchProvider.tileSize })
        #expect(frames.allSatisfy { $0.size == frames[0].size })
        for (left, right) in zip(frames, frames.dropFirst()) {
            #expect(left.maxX < right.minX)
        }
        #expect(host.hosting.fittingSize.width <= 600)
    }

    @Test("Disabled controls ignore actions; parent updates replace both selection and binding")
    func disabledAndParentUpdates() async throws {
        var previousChanges: [WebSearchProvider] = []
        var changes: [WebSearchProvider] = []
        let host = MenuControlTestHost(
            WebSearchProviderPicker(
                selection: Binding(get: { .firecrawl }, set: { previousChanges.append($0) })
            ).disabled(true),
            width: 600,
            height: 120
        )
        defer { host.close() }
        try await host.activateAccessibility()
        for name in ["None", "Firecrawl", "Tavily", "Brave", "Exa"] {
            let control = try host.element(label: name)
            #expect(!control.isAccessibilityEnabled())
            _ = control.accessibilityPerformPress()
        }
        #expect(previousChanges.isEmpty)

        host.hosting.rootView = WebSearchProviderPicker(
            selection: Binding(get: { .brave }, set: { changes.append($0) })
        ).disabled(false)
        host.render()
        let updated = try host.element(label: "Brave")
        #expect(updated.isAccessibilityEnabled())
        #expect(updated.object.isAccessibilitySelected?() == true)
        #expect(updated.accessibilityPerformPress())
        #expect(changes == [.brave])
        #expect(previousChanges.isEmpty)
    }

    private func hostPage() -> NSHostingView<WebSearchSettingsView> {
        let model = AppModel(
            snapshot: CoordinatorSnapshot(configuration: AppConfiguration(webSearch: .tavily))
        )
        let hosting = NSHostingView(
            rootView: WebSearchSettingsView(model: model, onSave: { _ in false }, onDraft: { _ in })
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 688, height: 620)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func descendant<NativeView: NSView>(
        _ type: NativeView.Type,
        in view: NSView
    ) -> NativeView? {
        if let result = view as? NativeView { return result }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
}

@MainActor
@Observable
private final class WebSearchControlDraft {
    var draft: WebSearchDraft

    init(configuration: WebSearchConfiguration) {
        draft = WebSearchDraft(configuration: configuration)
    }
}
