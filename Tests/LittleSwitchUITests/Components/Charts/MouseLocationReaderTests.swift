import AppKit
import Testing

@testable import LittleSwitchUI

@Suite("Mouse location reader")
@MainActor
struct MouseLocationReaderTests {
    @Test("Tracking follows window attachment and reports flipped local coordinates")
    func trackingAndReporting() throws {
        let view = MouseLocationReader.TrackingView(
            frame: NSRect(x: 0, y: 0, width: 20, height: 10)
        )
        var reported: [CGPoint?] = []
        view.onMoved = { reported.append($0) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 20, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view

        // Attachment enabled mouse-moved delivery and installed one area.
        #expect(window.acceptsMouseMovedEvents)
        #expect(view.trackingAreas.count == 1)

        // Rebuilding the area replaces the previous one instead of piling up.
        view.updateTrackingAreas()
        #expect(view.trackingAreas.count == 1)

        func movedEvent(_ point: NSPoint) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: point,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 0,
                    pressure: 0
                )
            )
        }

        func enterExitEvent(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try #require(
                NSEvent.enterExitEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    trackingNumber: 0,
                    userData: nil
                )
            )
        }

        view.mouseEntered(with: try enterExitEvent(.mouseEntered, at: NSPoint(x: 4, y: 4)))
        view.mouseMoved(with: try movedEvent(NSPoint(x: 6, y: 4)))
        view.mouseExited(with: try enterExitEvent(.mouseExited, at: NSPoint(x: 6, y: 4)))

        // The view is flipped: window y 4 in a 10-point-tall view reads 6.
        #expect(reported == [CGPoint(x: 4, y: 6), CGPoint(x: 6, y: 6), nil])
    }
}
