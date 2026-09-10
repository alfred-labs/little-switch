import AppKit
import SwiftUI

@MainActor
enum GatewayActivityMenuItemRenderer {
    static func apply(_ presentation: GatewayActivityPresentation, to item: NSMenuItem) {
        if let dashboard = presentation.menu.dashboard {
            applyDashboard(dashboard, to: item)
            return
        }
        applyAttributedTitle(presentation.menu, to: item)
    }

    private static func applyDashboard(
        _ dashboard: GatewayActivityPresentation.Menu.Dashboard,
        to item: NSMenuItem
    ) {
        let rootView = GatewayActivityDashboardView(
            runningCount: dashboard.runningCount,
            waitingCount: dashboard.waitingCount,
            stats: dashboard.stats,
            webSearch: dashboard.webSearch
        )
        let height = GatewayActivityDashboardView.height(stats: dashboard.stats)
        // Refresh in place: replacing an item's view while the menu tracks
        // tears down the row under the pointer, resets AppKit's highlight,
        // and steals the click headed for the item below. Same height keeps
        // the menu layout untouched; only a geometry change rebuilds.
        guard
            let hosting = item.view as? NSHostingView<GatewayActivityDashboardView>,
            hosting.frame.height == height
        else {
            // The retired view may sit in the warmup nursery, which would
            // keep it alive forever once the item stops referencing it.
            item.view?.removeFromSuperview()
            let replacement = Self.makeHostingView(rootView: rootView, height: height)
            item.view = replacement
            item.attributedTitle = nil
            item.title = ""
            item.image = nil
            // Warm after the assignment: NSMenuItem's view setter takes
            // ownership by detaching the view from its superview, which
            // would drop a view warmed inside makeHostingView from the
            // nursery before it ever rendered.
            StatusMenuHostedViewWarmup.warm(view: replacement)
            return
        }
        hosting.rootView = rootView
    }

    private static func makeHostingView(
        rootView: GatewayActivityDashboardView,
        height: CGFloat
    ) -> NSHostingView<GatewayActivityDashboardView> {
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: StatusMenuLayout.width,
            height: height
        )
        // The view replaces its predecessor mid-session (geometry change
        // while the menu is closed); its first opening must not be its
        // first layout, which renders blank until the menu reopens — the
        // caller warms it once it owns the view.
        return hosting
    }

    private static func applyAttributedTitle(
        _ menu: GatewayActivityPresentation.Menu,
        to item: NSMenuItem
    ) {
        // See the geometry-change branch: a nursery-adopted view must not
        // be kept alive by the warmup window once the item drops it.
        item.view?.removeFromSuperview()
        item.view = nil
        item.attributedTitle = NSAttributedString(
            string: menu.title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: NSFont.systemFontSize,
                    weight: .regular
                )
            ]
        )
        item.image = NSImage(
            systemSymbolName: menu.symbolName,
            accessibilityDescription: menu.accessibilityLabel
        )
        item.setAccessibilityLabel(menu.accessibilityLabel)
        item.setAccessibilityValue(menu.accessibilityValue)
        item.setAccessibilityHelp(menu.accessibilityHint)
    }
}
