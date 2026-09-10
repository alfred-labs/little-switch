import AppKit

/// What the menu-bar mark reports. `.active` means at least one application
/// currently routes through LittleSwitch.
enum StatusItemIconState: Equatable, Sendable {
    case idle
    case active
}

/// The exact drawing of one menu-bar state. Coordinates are points on the
/// 18-point canvas with a top-left origin, the convention of the approved
/// mockups, and every edge falls on a half point so the glyph rasterizes
/// without a soft pixel at 2x.
struct StatusItemIconGeometry: Equatable, Sendable {
    /// One switch module. `bounds` is the outer silhouette in both styles: an
    /// outlined module strokes a path inset by half the stroke width, so the
    /// two modules occupy boxes of the same size.
    struct Module: Equatable, Sendable {
        enum Style: Equatable, Sendable {
            /// Filled body with the indicator knocked out of it.
            case filled
            /// Stroked body with the indicator filled inside it.
            case outlined
        }

        let bounds: NSRect
        let style: Style
        let indicatorCenter: NSPoint
    }

    let size: NSSize
    let strokeWidth: CGFloat
    let cornerRadius: CGFloat
    let indicatorRadius: CGFloat
    let modules: [Module]
}

enum StatusItemIcon {
    /// The two modules never move. They sit offset with each indicator at its
    /// own end, which is the application icon's composition, and together they
    /// fill 17 of the canvas's 18 points so the mark holds its rank beside the
    /// system's own menu-bar symbols.
    private static func modules(fillingRight: Bool) -> [StatusItemIconGeometry.Module] {
        [
            StatusItemIconGeometry.Module(
                bounds: NSRect(x: 0.5, y: 0.5, width: 7.5, height: 15),
                style: fillingRight ? .outlined : .filled,
                indicatorCenter: NSPoint(x: 4.25, y: 4.25)
            ),
            StatusItemIconGeometry.Module(
                bounds: NSRect(x: 10, y: 2.5, width: 7.5, height: 15),
                style: fillingRight ? .filled : .outlined,
                indicatorCenter: NSPoint(x: 13.75, y: 13.75)
            ),
        ]
    }

    static let idleGeometry = StatusItemIconGeometry(
        size: NSSize(width: 18, height: 18),
        strokeWidth: 1,
        cornerRadius: 3.75,
        indicatorRadius: 1.75,
        modules: modules(fillingRight: false)
    )

    /// Switched on, the fill throws over to the right module the way a switch
    /// does. Nothing else changes: the capsules hold their places, and the mass
    /// moving across is the whole signal.
    static let activeGeometry = StatusItemIconGeometry(
        size: NSSize(width: 18, height: 18),
        strokeWidth: 1,
        cornerRadius: 3.75,
        indicatorRadius: 1.75,
        modules: modules(fillingRight: true)
    )

    static func geometry(for state: StatusItemIconState) -> StatusItemIconGeometry {
        switch state {
        case .idle:
            idleGeometry
        case .active:
            activeGeometry
        }
    }

    static func makeImage(for state: StatusItemIconState) -> NSImage {
        let geometry = StatusItemIcon.geometry(for: state)
        let image = NSImage(size: geometry.size, flipped: true) { _ in
            // The black only supplies the template image's alpha mask; macOS
            // owns the displayed foreground color.
            NSColor.black.setFill()
            NSColor.black.setStroke()
            for module in geometry.modules {
                draw(module, with: geometry)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(
        _ module: StatusItemIconGeometry.Module,
        with geometry: StatusItemIconGeometry
    ) {
        let indicator = NSBezierPath(
            ovalIn: NSRect(
                x: module.indicatorCenter.x - geometry.indicatorRadius,
                y: module.indicatorCenter.y - geometry.indicatorRadius,
                width: geometry.indicatorRadius * 2,
                height: geometry.indicatorRadius * 2
            )
        )
        switch module.style {
        case .filled:
            let body = NSBezierPath(
                roundedRect: module.bounds,
                xRadius: geometry.cornerRadius,
                yRadius: geometry.cornerRadius
            )
            body.append(indicator)
            // Even-odd is what turns the indicator into a hole instead of
            // painting it back over the body it sits in.
            body.windingRule = .evenOdd
            body.fill()
        case .outlined:
            // A stroke straddles its path, so the path is inset by half the
            // stroke width to land the outer edge exactly on `bounds`.
            let inset = geometry.strokeWidth / 2
            let body = NSBezierPath(
                roundedRect: module.bounds.insetBy(dx: inset, dy: inset),
                xRadius: geometry.cornerRadius - inset,
                yRadius: geometry.cornerRadius - inset
            )
            body.lineWidth = geometry.strokeWidth
            body.stroke()
            indicator.fill()
        }
    }
}
