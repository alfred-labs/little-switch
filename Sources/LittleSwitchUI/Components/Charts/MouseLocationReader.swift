import AppKit
import SwiftUI

/// Lightweight NSView-based pointer tracking with local coordinates, ported
/// from CodexBar's menu chart. SwiftUI's `onHover` carries no location, and
/// the dashboard needs it to name the hovered series bar.
@MainActor
struct MouseLocationReader: NSViewRepresentable {
    let onMoved: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMoved = onMoved
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMoved = onMoved
    }

    final class TrackingView: NSView {
        var onMoved: ((CGPoint?) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            updateTrackingAreas()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [
                    // Menu windows are never key, so `.activeInKeyWindow`
                    // would drop every move and the hover would flicker.
                    .activeAlways,
                    .inVisibleRect,
                    .mouseEnteredAndExited,
                    .mouseMoved,
                ],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onMoved?(nil)
        }
    }
}
