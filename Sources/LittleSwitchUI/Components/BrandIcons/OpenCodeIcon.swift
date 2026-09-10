import SwiftUI

// Native translation of LobeHub Icons' MIT-licensed OpenCode mono icon.
// Catalog: https://lobehub.com/icons/opencode
// Source: https://github.com/lobehub/lobe-icons/blob/
// 4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75/src/OpenCode/components/Mono.tsx
struct OpenCodeIcon: View {
    var body: some View {
        OpenCodeMark()
            .fill(Color.primary, style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
    }
}

private struct OpenCodeMark: Shape {
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
        path.move(to: point(16, 6))
        path.addLine(to: point(8, 6))
        path.addLine(to: point(8, 18))
        path.addLine(to: point(16, 18))
        path.addLine(to: point(16, 6))
        path.closeSubpath()

        path.move(to: point(20, 22))
        path.addLine(to: point(4, 22))
        path.addLine(to: point(4, 2))
        path.addLine(to: point(20, 2))
        path.addLine(to: point(20, 22))
        path.closeSubpath()
        return path
    }
}
