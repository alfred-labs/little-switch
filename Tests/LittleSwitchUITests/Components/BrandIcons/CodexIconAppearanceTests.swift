import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Codex icon appearance")
struct CodexIconAppearanceTests {
    @Test("The Codex mark stays visible on light and dark backgrounds", arguments: [ColorScheme.light, .dark])
    func visibleInBothAppearances(colorScheme: ColorScheme) throws {
        let background = colorScheme == .light ? Color.white : Color.black
        let colors = try pixels(
            of: CodexIcon()
                .frame(width: 32, height: 32)
                .background(background)
                .environment(\.colorScheme, colorScheme)
        )
        let backgroundBrightness: CGFloat = colorScheme == .light ? 1 : 0
        let visiblePixels = colors.filter { color in
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            return abs(brightness - backgroundBrightness) > 0.5
        }

        #expect(visiblePixels.count > colors.count / 10)
    }

    @Test("The Codex mark follows the owning control's foreground color")
    func inheritsForeground() throws {
        let colors = try pixels(
            of: CodexIcon()
                .foregroundStyle(Color(red: 1, green: 0, blue: 0))
                .frame(width: 32, height: 32)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        let tintedPixels = colors.filter { color in
            color.redComponent > 0.8 && color.greenComponent < 0.2 && color.blueComponent < 0.2
        }

        #expect(tintedPixels.count > colors.count / 10)
    }

    private func pixels<Content: View>(of content: Content) throws -> [NSColor] {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var colors: [NSColor] = []

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                colors.append(color)
            }
        }

        return colors
    }
}
