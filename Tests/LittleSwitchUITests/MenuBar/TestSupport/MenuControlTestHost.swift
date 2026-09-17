import AppKit
import ApplicationServices
import SwiftUI
import Testing

/// Exercises native hosted controls without displaying a window onscreen or
/// activating the application, changing preferences, or enabling accessibility.
@MainActor
final class MenuControlTestHost<Content: View> {
    let hosting: NSHostingView<Content>
    let window: NSWindow
    private weak var previousKeyWindow: NSWindow?
    private weak var previousFirstResponder: NSResponder?
    private var preparedKeyboardFocus = false

    init(_ content: Content, width: CGFloat = 320, height: CGFloat = 80) {
        MenuControlTestApplication.finishLaunching()
        hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let panel = MenuControlTestPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        window = panel
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        let leftEdge = NSScreen.screens.map(\.frame.minX).min() ?? 0
        let bottomEdge = NSScreen.screens.map(\.frame.minY).min() ?? 0
        window.setFrameOrigin(NSPoint(x: leftEdge - width - 100, y: bottomEdge - height - 100))
        window.orderBack(nil)
        render()
    }

    func activateAccessibility() async throws {
        // A client request materializes SwiftUI's lazy accessibility tree.
        // Query the application role so initialization does not depend on
        // AppKit publishing its changing window list. Only query this test
        // process, leaving MainActor free to answer the client request.
        let result = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var role: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role)
            return (status: status, role: role as? String)
        }.value
        try #require(result.status == .success, "Self-process accessibility request failed: \(result.status.rawValue)")
        try #require(result.role == kAXApplicationRole)
        render()
    }

    func prepareForKeyboardFocus() throws {
        if !preparedKeyboardFocus {
            previousKeyWindow = NSApp.keyWindow
            previousFirstResponder = previousKeyWindow?.firstResponder
            preparedKeyboardFocus = true
        }
        let wasActive = NSApp.isActive
        try #require(window.canBecomeKey, "The test panel must accept keyboard focus. \(focusDiagnostics)")
        if NSApp.isRunning, NSApp.isActive { window.makeKey() }
        try #require(window.makeFirstResponder(hosting), "The hosting view rejected focus. \(focusDiagnostics)")
        render()
        try #require(NSApp.isActive == wasActive, "Preparing focus activated the application. \(focusDiagnostics)")
    }

    func focus(label: String) async throws {
        try #require(preparedKeyboardFocus, "Prepare the test panel before focusing \(label). \(focusDiagnostics)")
        let wasActive = NSApp.isActive
        let target = try element(label: label)
        try #require(target.isAccessibilityEnabled(), "Cannot focus the disabled control \(label).")
        target.object.setAccessibilityFocused?(true)
        try await Task.sleep(for: .milliseconds(16))
        // macOS 27 can report SwiftUI semantic focus on the hosting container
        // instead of the leaf node. Keyboard behavior and drawn focus below
        // remain the assertions; this only accepts either public AX spelling.
        try await waitForFocus("Accessibility focus was not acquired by \(label)") {
            self.accessibilityElements.contains { $0.object.isAccessibilityFocused?() == true }
        }
        try #require(NSApp.isActive == wasActive, "Focusing \(label) activated the application. \(focusDiagnostics)")
    }

    func clearFocus() async throws {
        try #require(window.makeFirstResponder(nil), "The test panel rejected clearing focus. \(focusDiagnostics)")
        try await waitForFocus("Accessibility focus did not clear") {
            self.accessibilityElements.allSatisfy { $0.object.isAccessibilityFocused?() != true }
        }
    }

    func close() {
        let restorePreviousWindow = preparedKeyboardFocus && window.isKeyWindow
        _ = window.makeFirstResponder(nil)
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        if restorePreviousWindow, let previousKeyWindow, previousKeyWindow.isVisible {
            previousKeyWindow.makeKey()
            if let previousFirstResponder {
                _ = previousKeyWindow.makeFirstResponder(previousFirstResponder)
            }
        }
        previousKeyWindow = nil
        previousFirstResponder = nil
        preparedKeyboardFocus = false
    }

    func render() {
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func element(label: String) throws -> MenuControlAccessibilityElement {
        try #require(
            accessibilityElements.first { $0.accessibilityLabel() == label },
            "Native AX children: \(hosting.accessibilityChildren() ?? [])"
        )
    }

    var textContent: [String] {
        accessibilityElements.flatMap {
            [$0.accessibilityLabel(), $0.accessibilityValue() as? String].compactMap(\.self)
        }
    }

    var accessibilityElements: [MenuControlAccessibilityElement] {
        var pending: [Any] = [hosting]
        var visited = Set<ObjectIdentifier>()
        var elements: [MenuControlAccessibilityElement] = []
        while let candidate = pending.popLast() {
            let object = candidate as AnyObject
            guard visited.insert(ObjectIdentifier(object)).inserted else {
                continue
            }
            let element = MenuControlAccessibilityElement(object: object)
            elements.append(element)
            pending.append(contentsOf: element.accessibilityChildren())
        }
        return elements
    }

    func nativeView<T: NSView>(of type: T.Type) throws -> T {
        try #require(Self.descendants(of: hosting).compactMap { $0 as? T }.first)
    }

    private func waitForFocus(_ description: String, matching condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var matched = false
        repeat {
            try Task.checkCancellation()
            render()
            matched = condition()
            if matched { break }
            try await Task.sleep(for: .milliseconds(16))
        } while ContinuousClock.now < deadline
        try #require(matched, "\(description). \(focusDiagnostics)")
    }

    private var focusDiagnostics: String {
        let focused = accessibilityElements.filter { $0.object.isAccessibilityFocused?() == true }
            .map { $0.accessibilityLabel() ?? String(describing: type(of: $0.object)) }
        return "active=\(NSApp.isActive), visible=\(window.isVisible), canBecomeKey=\(window.canBecomeKey), "
            + "key=\(window.isKeyWindow), responder=\(String(describing: window.firstResponder)), focused=\(focused)"
    }

    private static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

}

@MainActor
private final class MenuControlTestPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private enum MenuControlTestApplication {
    private static var didFinishLaunching = false

    static func finishLaunching() {
        guard !NSApplication.shared.isRunning else { return }
        guard !didFinishLaunching else { return }
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        // finishLaunching starts AppKit's accessibility server and normally
        // activates the app. Prohibit activation during this test-only startup.
        application.setActivationPolicy(.prohibited)
        defer { application.setActivationPolicy(originalPolicy) }
        application.finishLaunching()
        didFinishLaunching = true
    }
}

/// SwiftUI can expose Objective-C accessibility selectors on objects that
/// do not formally adopt the complete NSAccessibilityProtocol at runtime.
/// Dispatch the public selectors just as AppKit's accessibility bridge does.
@MainActor
struct MenuControlAccessibilityElement {
    let object: AnyObject

    func accessibilityLabel() -> String? {
        object.accessibilityLabel?()
    }

    func accessibilityValue() -> Any? {
        object.accessibilityValue?()
    }

    func accessibilityValueDescription() -> String? {
        object.accessibilityValueDescription?()
    }

    func accessibilityRole() -> NSAccessibility.Role? {
        object.accessibilityRole?()
    }

    func isAccessibilityEnabled() -> Bool {
        object.isAccessibilityEnabled?() ?? false
    }

    func accessibilityChildren() -> [Any] {
        object.accessibilityChildren?() ?? []
    }

    func accessibilityPerformPress() -> Bool {
        object.accessibilityPerformPress?() ?? false
    }

    func accessibilityPerformIncrement() -> Bool {
        object.accessibilityPerformIncrement?() ?? false
    }

    func accessibilityPerformDecrement() -> Bool {
        object.accessibilityPerformDecrement?() ?? false
    }
}
