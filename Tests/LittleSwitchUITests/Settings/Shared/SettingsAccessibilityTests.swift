import AppKit
import ApplicationServices
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Settings accessibility boundaries", .serialized)
struct SettingsAccessibilityTests {
    @Test("Toolbar status and actions retain independent names through the AX bridge", arguments: [false, true])
    func toolbarActionNames(disabled: Bool) async throws {
        let bootstrap = MenuControlTestHost(Text("Accessibility initialization"))
        defer { bootstrap.close() }
        let page = SettingsAccessibilityPage()
        let controller = NSHostingController(
            rootView: SettingsAccessibilityToolbarPage(page: page, disabled: disabled)
        )
        let window = NSWindow(contentViewController: controller)
        let windowIdentifier = "LittleSwitch.SettingsAccessibilityTests.\(UUID().uuidString)"
        window.setAccessibilityIdentifier(windowIdentifier)
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

        let initial = try await eventually(description: "initial toolbar status reaches external accessibility") {
            let elements = await SettingsExternalAccessibility.snapshot(windowIdentifier: windowIdentifier)
            return elements.contains { $0.value == "Not connected" } ? elements : nil
        }
        let status = try #require(initial.first { $0.value == "Not connected" }, "\(initial)")
        #expect(status.description == nil || status.description == "Not connected")

        page.showsExport = true
        try await bootstrap.activateAccessibility()
        controller.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let toolbar = try #require(window.toolbar)
        let elements = toolbar.items.compactMap(\.view).flatMap { descendants(of: $0) }
        let testExport = try #require(elements.first { $0.object.accessibilityHelp?() == "Send a synthetic event" })
        let apply = try #require(elements.first { $0.object.accessibilityHelp?() == "Apply monitoring settings" })
        #expect(testExport.accessibilityLabel() == "Test export")
        #expect(apply.accessibilityLabel() == "Apply")
        #expect(testExport.isAccessibilityEnabled() == !disabled)
        #expect(apply.isAccessibilityEnabled() == !disabled)

        // SwiftUI publishes the rebuilt toolbar to external AX clients after
        // the native views exist. Help can arrive before the other attributes;
        // wait for every inspected button attribute to be present, then assert
        // the exact names, roles and enabled states below.
        let external: [SettingsExternalAccessibility.Element] = try await eventually(
            description: "updated toolbar actions reach external accessibility"
        ) {
            let elements = await SettingsExternalAccessibility.snapshot(windowIdentifier: windowIdentifier)
            guard let test = elements.first(where: { $0.help == "Send a synthetic event" }),
                let apply = elements.first(where: { $0.help == "Apply monitoring settings" }),
                test.role != nil, test.description != nil, test.enabled != nil,
                apply.role != nil, apply.description != nil, apply.enabled != nil
            else {
                return nil
            }
            return elements
        }
        let externalTest = try #require(external.first { $0.help == "Send a synthetic event" }, "\(external)")
        let externalApply = try #require(external.first { $0.help == "Apply monitoring settings" }, "\(external)")
        #expect(externalTest.role == kAXButtonRole)
        #expect(externalApply.role == kAXButtonRole)
        #expect(externalTest.description == "Test export")
        #expect(externalApply.description == "Apply")
        #expect(externalTest.enabled == !disabled)
        #expect(externalApply.enabled == !disabled)
    }

    @Test("Export settings preserve independent disclosure, switch and receiver names")
    func exportFieldNames() async throws {
        let host = MenuControlTestHost(
            MonitoringDestinationFields(
                title: "Metrics",
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
                $0.object.accessibilityHelp?() == "Apply changes to update this export."
            }
        )
        let receiver = try #require(
            host.accessibilityElements.first {
                $0.object.accessibilityHelp?() == "Use the complete OTLP receiver URL, including its metrics path."
            }
        )
        #expect(toggle.accessibilityLabel() == "Export metrics")
        #expect(receiver.accessibilityLabel() == "Metrics receiver URL")
        let disclosure = try #require(
            host.accessibilityElements.first {
                $0.object.accessibilityHelp?() == "Show or hide metrics export settings."
            }
        )
        #expect(disclosure.accessibilityPerformPress())
        host.render()
        #expect(!host.textContent.contains("Metrics receiver URL"))
        #expect(host.textContent.contains("Export metrics"))
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

/// Read the same public AX attributes an external accessibility client receives.
/// The client stays off MainActor so AppKit can answer its synchronous requests.
private enum SettingsExternalAccessibility {
    struct Element: Sendable {
        let role: String?
        let description: String?
        let value: String?
        let help: String?
        let enabled: Bool?
    }

    static func snapshot(windowIdentifier: String) async -> [Element] {
        let processID = ProcessInfo.processInfo.processIdentifier
        return await Task.detached {
            let application = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(application, 2)
            let windows = attribute(kAXWindowsAttribute, from: application) as? [AXUIElement] ?? []
            var pending = windows.filter {
                // During AX startup these handles can still describe the
                // application. Resolve their role before matching a window.
                attribute(kAXRoleAttribute, from: $0) as? String == kAXWindowRole
                    && attribute(kAXIdentifierAttribute, from: $0) as? String == windowIdentifier
            }
            var visited: [AXUIElement] = []
            var result: [Element] = []
            while let element = pending.popLast() {
                guard !visited.contains(where: { CFEqual($0, element) }) else { continue }
                visited.append(element)
                result.append(
                    Element(
                        role: attribute(kAXRoleAttribute, from: element) as? String,
                        description: attribute(kAXDescriptionAttribute, from: element) as? String,
                        value: attribute(kAXValueAttribute, from: element) as? String,
                        help: attribute(kAXHelpAttribute, from: element) as? String,
                        enabled: attribute(kAXEnabledAttribute, from: element) as? Bool
                    )
                )
                pending.append(contentsOf: attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] ?? [])
            }
            return result
        }.value
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
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
                        Button("Test export") {}
                            .disabled(disabled)
                            .help("Send a synthetic event")
                        Button("Apply", systemImage: "checkmark") {}
                            .disabled(disabled)
                            .accessibilityHint("Apply monitoring settings")
                    }
                }
            } else {
                Color.clear.toolbar {
                    SettingsToolbarActions {
                        SettingsConnectionStatus(connected: false)
                        Button("Apply", systemImage: "checkmark") {}
                            .disabled(disabled)
                            .accessibilityHint("Apply client settings")
                    }
                }
            }
        }
        .settingsWindowTitle("Monitoring")
    }
}
