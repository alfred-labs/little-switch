import AppKit
import SwiftUI

@MainActor
enum SettingsWindowFactory {
    static func make(hosting view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsLayout.windowWidth,
                height: SettingsLayout.windowHeight
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        let controller = NSHostingController(rootView: view)
        // Let the SwiftUI content minimum own the native resize constraint.
        controller.sizingOptions = [.minSize]
        window.contentViewController = controller
        SettingsWindowChrome.apply(to: window)
        window.setFrame(
            NSRect(
                origin: window.frame.origin,
                size: NSSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
            ),
            display: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}
