import AppKit
import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Menu application hover", .appKitIsolation)
struct MenuApplicationHoverTests {
    @Test("Only app icons highlight, without changing the cursor or focus", arguments: [false, true])
    func iconFeedback(dark: Bool) async throws {
        let model = AppModel()
        model.desktopApplications = .init(claude: .available, codex: .available, openCode: .available)
        let host = makeHost(model)
        defer { host.close() }
        host.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try await host.activateAccessibility()
        let wasActive = NSApp.isActive
        let cursor = NSCursor.current
        defer { cursor.set() }
        let resting = try pixels(host)
        var entering = true
        for application in DesktopApplication.allCases {
            let point = try iconCenter(application, in: host)
            try await move(host, to: point, entering: entering)
            entering = false
            #expect(try pixels(host) != resting)
            #expect(NSCursor.current == cursor)
            try await move(host, to: NSPoint(x: point.x + 60, y: point.y))
            #expect(try pixels(host) == resting)
        }
        #expect(!host.window.isKeyWindow)
        #expect(NSApp.isActive == wasActive)
    }

    @Test("Unavailable and busy icons have no hover feedback", arguments: 0..<4)
    func disabledFeedback(state: Int) async throws {
        let model = AppModel()
        model.desktopApplications = .init(claude: .available)
        switch state {
        case 0: model.desktopApplications.claude = .notInstalled
        case 1: model.desktopApplications.claude = .organizationManaged
        case 2: model.launchingApplications = [.claude]
        default: model.isBusy = true
        }
        let host = makeHost(model)
        defer { host.close() }
        try await host.activateAccessibility()
        let resting = try pixels(host)
        try await move(host, to: iconCenter(.claude, in: host), entering: true)
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(25))
            #expect(try pixels(host) == resting)
        }
    }

    @Test("Becoming busy clears feedback without another move; detachment clears hover")
    func hoverLifecycle() async throws {
        let model = AppModel()
        model.desktopApplications = .init(claude: .available)
        let host = makeHost(model)
        defer { host.close() }
        try await host.activateAccessibility()
        let resting = try pixels(host)
        let point = try iconCenter(.claude, in: host)
        try await move(host, to: point, entering: true)
        #expect(try pixels(host) != resting)

        model.isBusy = true
        try await Task.sleep(for: .milliseconds(40))
        let disabledWhileHovered = try pixels(host)
        try await move(host, to: NSPoint(x: point.x + 60, y: point.y))
        #expect(try pixels(host) == disabledWhileHovered)

        model.isBusy = false
        try await Task.sleep(for: .milliseconds(40))
        try await move(host, to: point)
        #expect(try pixels(host) != resting)
        host.window.contentView = nil
        try await Task.sleep(for: .milliseconds(40))
        host.window.contentView = host.hosting
        try await Task.sleep(for: .milliseconds(40))
        #expect(try pixels(host) == resting)
    }

    private func makeHost(_ model: AppModel) -> MenuControlTestHost<MenuStatusView> {
        MenuControlTestHost(
            MenuStatusView(
                model: model, onToggleClaude: {}, onToggleClaudeCode: {}, onToggleCodex: {}, onToggleOpenCode: {}),
            height: StatusMenuLayout.applicationBlockHeight
        )
    }

    private func iconCenter(
        _ application: DesktopApplication, in host: MenuControlTestHost<MenuStatusView>
    ) throws -> NSPoint {
        let button = try host.element(label: L10n.string("Open \(application.displayName)"))
        let frame = try #require(button.object.accessibilityFrame?())
        return host.window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
    }

    private func pixels(_ host: MenuControlTestHost<MenuStatusView>) throws -> Data {
        host.render()
        let view = host.hosting
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    // Component-level render test: native event delivery is additionally
    // exercised with the real pointer in a non-activating menu during UI QA.
    private func move(
        _ host: MenuControlTestHost<MenuStatusView>, to point: NSPoint, entering: Bool = false
    ) async throws {
        let event = try #require(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: host.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            ))
        host.hosting.updateTrackingAreas()
        for area in host.hosting.trackingAreas where area.options.contains(.mouseMoved) {
            let owner = area.owner as AnyObject?
            if entering { owner?.mouseEntered?(with: EnteredEvent(event, area: area)) }
            owner?.mouseMoved?(with: event)
        }
        try await Task.sleep(for: .milliseconds(40))
    }

    private final class EnteredEvent: NSEvent {
        private let wrapped: NSEvent
        private let area: NSTrackingArea

        init(_ event: NSEvent, area: NSTrackingArea) {
            wrapped = event
            self.area = area
            super.init()
        }

        required init?(coder: NSCoder) { nil }

        override var type: NSEvent.EventType { .mouseEntered }
        override var locationInWindow: NSPoint { wrapped.locationInWindow }
        override var timestamp: TimeInterval { wrapped.timestamp }
        override var window: NSWindow? { wrapped.window }
        override var windowNumber: Int { wrapped.windowNumber }
        override var modifierFlags: NSEvent.ModifierFlags { wrapped.modifierFlags }
        override var trackingArea: NSTrackingArea? { area }
        override var eventNumber: Int { wrapped.eventNumber }
        override var trackingNumber: Int { 0 }
        override var userData: UnsafeMutableRawPointer? { nil }
    }
}
