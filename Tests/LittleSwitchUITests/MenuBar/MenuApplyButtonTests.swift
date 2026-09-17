import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Menu Apply button", .appKitIsolation)
struct MenuApplyButtonTests {
    @Test("The accessible Return button dispatches and follows its live disabled state")
    func activationAndDisabledState() async throws {
        let model = AppModel()
        var calls = 0
        let action = MenuApplyAction(isEnabled: !model.isBusy) { calls += 1 }
        func content() -> some View {
            MenuApplyButton(action: action)
                .padding(10)
        }
        let host = MenuControlTestHost(content(), width: 60, height: 50)
        defer { host.close() }
        host.window.appearance = NSAppearance(named: .darkAqua)
        try await host.activateAccessibility()
        let button = try host.element(label: L10n.string("Apply changes"))
        #expect(button.accessibilityRole() == .button)
        #expect(button.isAccessibilityEnabled())
        #expect(button.accessibilityPerformPress())
        #expect(calls == 1)

        model.isBusy = true
        host.hosting.rootView = content()
        host.render()
        let disabled = try host.element(label: L10n.string("Apply changes"))
        #expect(!disabled.isAccessibilityEnabled())
        _ = disabled.accessibilityPerformPress()
        #expect(calls == 1)

        model.isBusy = false
        host.hosting.rootView = content()
        host.render()
        #expect(try host.element(label: L10n.string("Apply changes")).accessibilityPerformPress())
        #expect(calls == 2)
    }

    @Test("Hover highlights only an enabled button and clears on exit", arguments: [true, false])
    func hoverFeedback(isEnabled: Bool) async throws {
        var calls = 0
        let action = MenuApplyAction(isEnabled: isEnabled) { calls += 1 }
        let host = MenuControlTestHost(MenuApplyButton(action: action).padding(10), width: 60, height: 50)
        defer { host.close() }
        try await host.activateAccessibility()
        let wasActive = NSApp.isActive
        let resting = try pixels(of: host.hosting)

        host.hosting.updateTrackingAreas()
        try hover(true, in: host.hosting)
        let didRenderHover: Bool
        if isEnabled {
            didRenderHover = try await renders(host.hosting) { $0 != resting }
        } else {
            // A negative assertion must survive deferred SwiftUI updates,
            // rather than accepting the first unchanged frame after entry.
            didRenderHover = try await remainsStable(host.hosting, pixels: resting)
        }
        #expect(didRenderHover)

        try hover(false, in: host.hosting)
        let didClearHover = try await renders(host.hosting) { $0 == resting }
        #expect(didClearHover)
        #expect(calls == 0)
        #expect(NSApp.isActive == wasActive)
    }

    @Test("Accessibility focus draws and clears the keyboard focus ring without activation")
    func focusFeedback() async throws {
        let action = MenuApplyAction(isEnabled: true) {}
        let host = MenuControlTestHost(MenuApplyButton(action: action).padding(10), width: 60, height: 50)
        defer { host.close() }
        try await host.activateAccessibility()
        let wasActive = NSApp.isActive
        try host.prepareForKeyboardFocus()
        try await host.clearFocus()
        let resting = try pixels(of: host.hosting)
        let button = try host.element(label: L10n.string("Apply changes"))
        #expect(button.object.isAccessibilityFocused?() == false)

        // The native accessibility action focuses this control even when
        // keyboard navigation is off in the user's system preferences.
        try await host.focus(label: L10n.string("Apply changes"))
        let didRenderFocus = try await renders(host.hosting) { $0 != resting }
        #expect(didRenderFocus)
        #expect(host.accessibilityElements.contains { $0.object.isAccessibilityFocused?() == true })

        try await host.clearFocus()
        let didClearFocus = try await renders(host.hosting) { $0 == resting }
        #expect(didClearFocus)
        #expect(try host.element(label: L10n.string("Apply changes")).object.isAccessibilityFocused?() == false)
        #expect(NSApp.isActive == wasActive)
    }

    private func hover(_ entered: Bool, in view: NSView) throws {
        let window = try #require(view.window)
        let baseEvent = try #require(
            NSEvent.enterExitEvent(
                with: entered ? .mouseEntered : .mouseExited,
                location: NSPoint(x: view.bounds.midX, y: view.bounds.midY),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            )
        )
        #expect(!view.trackingAreas.isEmpty)
        for area in view.trackingAreas {
            let owner = area.owner as AnyObject?
            let event = TrackingEvent(baseEvent, area: area)
            if event.type == .mouseEntered {
                owner?.mouseEntered?(with: event)
            } else {
                owner?.mouseExited?(with: event)
            }
        }
    }

    /// NSEvent's public factory creates a legacy rectangle event without a
    /// trackingArea. Supply the installed area when delivering to its owner,
    /// as AppKit does for an actual pointer transition.
    private final class TrackingEvent: NSEvent {
        private let wrapped: NSEvent
        private let area: NSTrackingArea

        init(_ event: NSEvent, area: NSTrackingArea) {
            wrapped = event
            self.area = area
            super.init()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var type: NSEvent.EventType { wrapped.type }
        override var locationInWindow: NSPoint { wrapped.locationInWindow }
        override var timestamp: TimeInterval { wrapped.timestamp }
        override var window: NSWindow? { wrapped.window }
        override var windowNumber: Int { wrapped.windowNumber }
        override var modifierFlags: NSEvent.ModifierFlags { wrapped.modifierFlags }
        override var trackingArea: NSTrackingArea? { area }
        override var eventNumber: Int { wrapped.eventNumber }
        override var trackingNumber: Int { wrapped.trackingNumber }
        override var userData: UnsafeMutableRawPointer? { wrapped.userData }
    }

    private func pixels(of view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private func renders(_ view: NSView, matching condition: (Data) -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        repeat {
            try await Task.sleep(for: .milliseconds(16))
            if try condition(pixels(of: view)) { return true }
        } while ContinuousClock.now < deadline
        return false
    }

    private func remainsStable(_ view: NSView, pixels expected: Data) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        repeat {
            try await Task.sleep(for: .milliseconds(16))
            if try pixels(of: view) != expected { return false }
        } while ContinuousClock.now < deadline
        return true
    }
}
