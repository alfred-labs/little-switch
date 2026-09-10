import AppKit

/// Keeps the status menu's hosted SwiftUI rows rendered while they are not
/// inside the open menu's window.
///
/// An `NSHostingView` only builds and renders its SwiftUI content during a
/// display pass over a window. The rows hosted through `NSMenuItem.view`
/// spend their life detached — the menu window exists only while tracking —
/// so a row that was created or updated while the menu was closed can open
/// blank: AppKit enters event tracking before any display pass runs for the
/// freshly attached view, and the row only appears after the menu closes
/// and reopens (the "empty switches, fixed on reopen" glitch).
///
/// The fix is a borderless offscreen window acting as a nursery. Attaching
/// a detached row to it and forcing `displayIfNeeded()` renders the row
/// synchronously — no screen presence, no run-loop turn. The row is then
/// detached again before the menu opens, because the menu window only
/// adopts rows that have no superview: a row left attached to the nursery
/// is sized into the menu layout but never shown in it, so every hosted
/// row would open blank on every opening.
@MainActor
enum StatusMenuHostedViewWarmup {
    private static var nurseryWindow: NSWindow?

    /// Renders rows hosted by the menu: detached rows are adopted by the
    /// nursery and displayed; rows already inside a window (typically the
    /// opening menu's) are laid out and displayed in place.
    static func warm(menu: NSMenu) {
        for item in menu.items {
            guard let view = item.view else {
                continue
            }
            // AppKit retains windowless item viewers between openings.
            // Refresh the hosted row directly so that viewer cannot keep
            // SwiftUI's colors tied to the previous menu appearance.
            view.appearance = menu.effectiveAppearance
            warm(view: view)
        }
    }

    /// Completes the hosted view's SwiftUI render in one synchronous pass
    /// and leaves a detached view detached: the menu window only adopts
    /// rows without a superview.
    ///
    /// The detached check is `superview`, not `window`: between openings,
    /// the status menu keeps its item viewers alive, and a row sits inside
    /// one with no window — `window == nil` would misread that row as
    /// detached, rip it out of its viewer, and leave the menu showing an
    /// empty slot on every subsequent opening.
    static func warm(view: NSView) {
        if view.superview == nil {
            nursery().contentView?.addSubview(view)
            nursery().displayIfNeeded()
            // Detach after the render: AppKit's menu window never adopts a
            // view that already has a superview in another window — the
            // row is sized into the menu layout but rendered nowhere the
            // user can see. The render above survives the detach, and the
            // menu re-parents the row when it next opens.
            view.removeFromSuperview()
            return
        }
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
    }

    private static func nursery() -> NSWindow {
        if let nurseryWindow {
            return nurseryWindow
        }
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: StatusMenuLayout.width,
                height: 4_096
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        nurseryWindow = window
        return window
    }
}

extension StatusItemController: NSMenuDelegate {
    /// Arm native shortcuts and finish deferred SwiftUI layout before
    /// AppKit enters the menu tracking loop.
    func menuWillOpen(_ menu: NSMenu) {
        // A retained menu must follow appearance changes between openings.
        // Keep the complete appearance, including accessibility contrast.
        menu.appearance = NSApp.effectiveAppearance
        for case let item as MenuApplyMenuItem in menu.items {
            item.setTracking(true)
        }
        StatusMenuHostedViewWarmup.warm(menu: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        for case let item as MenuApplyMenuItem in menu.items {
            item.setTracking(false)
        }
    }
}
