import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Settings accessibility boundaries", .serialized)
struct SettingsAccessibilityTests {
    @Test("Toolbar status and actions retain independent accessibility names", arguments: [false, true])
    func toolbarActionNames(disabled: Bool) async throws {
        let bootstrap = MenuControlTestHost(Text("Accessibility initialization"))
        defer { bootstrap.close() }
        let page = SettingsAccessibilityPage()
        let controller = NSHostingController(
            rootView: SettingsAccessibilityToolbarPage(page: page, disabled: disabled)
        )
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil)
            window.close()
        }
        SettingsWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: 1_200, height: 840))
        let leftEdge = NSScreen.screens.map(\.frame.minX).min() ?? 0
        window.setFrameOrigin(NSPoint(x: leftEdge - 1_400, y: -1_000))
        window.orderBack(nil)
        try await bootstrap.activateAccessibility()
        controller.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let toolbar = try #require(window.toolbar)
        let initialElements = toolbar.items.compactMap(\.view).flatMap { descendants(of: $0) }
        let status = try #require(
            initialElements.first { $0.accessibilityValue() as? String == L10n.string("Not connected") },
            "\(initialElements)"
        )
        #expect(status.accessibilityRole() == .staticText)
        page.showsExport = true
        try await bootstrap.activateAccessibility()
        controller.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let elements = toolbar.items.compactMap(\.view).flatMap { descendants(of: $0) }
        let testExport = try #require(elements.first { $0.object.accessibilityHelp?() == "Send a synthetic event" })
        let apply = try #require(
            elements.first { $0.object.accessibilityHelp?() == L10n.string("Apply monitoring settings") })
        #expect(testExport.accessibilityLabel() == L10n.string("Test export"))
        #expect(apply.accessibilityLabel() == L10n.string("Apply"))
        #expect(testExport.isAccessibilityEnabled() == !disabled)
        #expect(apply.isAccessibilityEnabled() == !disabled)

        #expect(testExport.accessibilityRole() == .button)
        #expect(apply.accessibilityRole() == .button)
    }

    @Test("Export settings preserve independent disclosure, switch and receiver names")
    func exportFieldNames() async throws {
        let host = MenuControlTestHost(
            MonitoringDestinationFields(
                title: L10n.string("Metrics"),
                placeholder: "https://collector.example/v1/metrics",
                destination: .constant(.init(enabled: true)),
                token: .constant(""),
                removeToken: .constant(false),
                pending: false,
                status: .init(state: .disabled),
                testResult: nil
            ) { EmptyView() },
            width: 688,
            height: 400
        )
        defer { host.close() }
        try await host.activateAccessibility()
        let toggle = try #require(
            host.accessibilityElements.first {
                $0.object.accessibilityHelp?() == L10n.string("Apply changes to update this export.")
            }
        )
        let receiver = try #require(
            host.accessibilityElements.first {
                $0.object.accessibilityHelp?()
                    == L10n.string(
                        "Use the complete OTLP receiver URL, including its \(L10n.string("Metrics").lowercased()) path."
                    )
            }
        )
        #expect(
            toggle.accessibilityLabel()
                == L10n.string("Export \(L10n.string("Metrics").lowercased())")
        )
        #expect(
            receiver.accessibilityLabel()
                == L10n.string("\(L10n.string("Metrics")) receiver URL")
        )
        let disclosure = try #require(
            host.accessibilityElements.first {
                $0.object.accessibilityHelp?()
                    == L10n.string(
                        "Show or hide \(L10n.string("Metrics").lowercased()) export settings."
                    )
            }
        )
        #expect(disclosure.accessibilityPerformPress())
        host.render()
        #expect(!host.textContent.contains(L10n.string("\(L10n.string("Metrics")) receiver URL")))
        #expect(host.textContent.contains(L10n.string("Export \(L10n.string("Metrics").lowercased())")))
    }

    private func descendants(of root: AnyObject) -> [MenuControlAccessibilityElement] {
        var pending: [Any] = [root]
        var visited = Set<ObjectIdentifier>()
        var elements: [MenuControlAccessibilityElement] = []
        while let candidate = pending.popLast() {
            let object = candidate as AnyObject
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let element = MenuControlAccessibilityElement(object: object)
            elements.append(element)
            pending.append(contentsOf: element.accessibilityChildren())
        }
        return elements
    }
}

@MainActor
@Observable
private final class SettingsAccessibilityPage {
    var showsExport = false
}

private struct SettingsAccessibilityToolbarPage: View {
    let page: SettingsAccessibilityPage
    let disabled: Bool

    var body: some View {
        SettingsSplitView(isSidebarVisible: .constant(true)) {
            Text("Sidebar")
        } detail: {
            if page.showsExport {
                Color.clear.toolbar {
                    SettingsToolbarActions {
                        Button(L10n.string("Test export")) {}
                            .disabled(disabled)
                            .help("Send a synthetic event")
                        Button(L10n.string("Apply"), systemImage: "checkmark") {}
                            .disabled(disabled)
                            .accessibilityHint(L10n.string("Apply monitoring settings"))
                    }
                }
            } else {
                Color.clear.toolbar {
                    SettingsToolbarActions {
                        SettingsConnectionStatus(connected: false)
                        Button(L10n.string("Apply"), systemImage: "checkmark") {}
                            .disabled(disabled)
                            .accessibilityHint("Apply client settings")
                    }
                }
            }
        }
        .settingsWindowTitle(L10n.string("Monitoring"))
    }
}
