import AppKit
import ApplicationServices
import SwiftUI
import Testing

/// Exercises native hosted controls without ordering a window onscreen or
/// changing application focus, system preferences, or accessibility settings.
@MainActor
final class MenuControlTestHost<Content: View> {
    let hosting: NSHostingView<Content>
    let window: NSWindow

    init(_ content: Content, width: CGFloat = 320, height: CGFloat = 80) {
        MenuControlTestApplication.finishLaunching()
        hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
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

    private static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}

@MainActor
private enum MenuControlTestApplication {
    private static var didFinishLaunching = false

    static func finishLaunching() {
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
