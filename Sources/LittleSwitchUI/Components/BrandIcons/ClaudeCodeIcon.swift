import SwiftUI

// Native translation of LobeHub Icons' MIT-licensed Claude Code color icon.
// Catalog: https://lobehub.com/icons/claudecode
// Source: https://github.com/lobehub/lobe-icons/blob/
// 4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75/src/ClaudeCode/components/Color.tsx
struct ClaudeCodeIcon: View {
    private static let brandColor = Color(
        red: 217.0 / 255.0,
        green: 119.0 / 255.0,
        blue: 87.0 / 255.0
    )

    var body: some View {
        ClaudeCodeMark()
            .fill(Self.brandColor, style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
    }
}

private struct ClaudeCodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let origin = CGPoint(
            x: rect.minX + (rect.width - (24 * scale)) / 2,
            y: rect.minY + (rect.height - (24 * scale)) / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (x * scale), y: origin.y + (y * scale))
        }

        var path = Path()
        path.move(to: point(20.998, 10.949))
        path.addLine(to: point(24, 10.949))
        path.addLine(to: point(24, 14.051))
        path.addLine(to: point(21, 14.051))
        path.addLine(to: point(21, 17.079))
        path.addLine(to: point(19.513, 17.079))
        path.addLine(to: point(19.513, 20))
        path.addLine(to: point(18, 20))
        path.addLine(to: point(18, 17.079))
        path.addLine(to: point(16.513, 17.079))
        path.addLine(to: point(16.513, 20))
        path.addLine(to: point(15, 20))
        path.addLine(to: point(15, 17.079))
        path.addLine(to: point(9, 17.079))
        path.addLine(to: point(9, 20))
        path.addLine(to: point(7.488, 20))
        path.addLine(to: point(7.488, 17.079))
        path.addLine(to: point(6, 17.079))
        path.addLine(to: point(6, 20))
        path.addLine(to: point(4.487, 20))
        path.addLine(to: point(4.487, 17.079))
        path.addLine(to: point(3, 17.079))
        path.addLine(to: point(3, 14.05))
        path.addLine(to: point(0, 14.05))
        path.addLine(to: point(0, 10.95))
        path.addLine(to: point(3, 10.95))
        path.addLine(to: point(3, 5))
        path.addLine(to: point(20.998, 5))
        path.closeSubpath()

        path.move(to: point(6, 10.949))
        path.addLine(to: point(7.488, 10.949))
        path.addLine(to: point(7.488, 8.102))
        path.addLine(to: point(6, 8.102))
        path.closeSubpath()

        path.move(to: point(16.51, 10.949))
        path.addLine(to: point(18, 10.949))
        path.addLine(to: point(18, 8.102))
        path.addLine(to: point(16.51, 8.102))
        path.closeSubpath()
        return path
    }
}
