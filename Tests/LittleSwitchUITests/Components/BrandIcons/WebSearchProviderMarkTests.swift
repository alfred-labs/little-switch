import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@Suite("Web search provider marks")
@MainActor
struct WebSearchProviderMarkTests {
    @Test("Each provider mark parses into a 24 point template image")
    func templateImages() throws {
        let images = [
            ("Firecrawl", try #require(FirecrawlIcon.templateImage())),
            ("Tavily", try #require(TavilyIcon.templateImage())),
            ("Brave", try #require(BraveIcon.templateImage())),
            ("Exa", try #require(ExaIcon.templateImage())),
        ]

        for (name, image) in images {
            #expect(image.size == NSSize(width: 24, height: 24), "\(name) keeps the upstream view box")
            #expect(image.isTemplate, "\(name) lets the owning control supply the tint")
        }
    }

    @Test("Rendered marks draw ink in the mark area and stay clear in the corners")
    func renderedInk() throws {
        let images = [
            ("Firecrawl", try #require(FirecrawlIcon.templateImage())),
            ("Tavily", try #require(TavilyIcon.templateImage())),
            ("Brave", try #require(BraveIcon.templateImage())),
            ("Exa", try #require(ExaIcon.templateImage())),
        ]

        for (name, image) in images {
            let raster = try MarkRaster(image: image)

            #expect(
                raster.maximumAlpha(inTopOriginRect: NSRect(x: 8, y: 2, width: 8, height: 20)) > 0.1,
                "\(name) should draw its mark through the central band"
            )
            // Tavily's pen tip owns the top-left corner, so only the three
            // remaining corners are shared clear regions.
            for corner in [
                NSRect(x: 22, y: 0, width: 2, height: 2),
                NSRect(x: 0, y: 22, width: 2, height: 2),
                NSRect(x: 22, y: 22, width: 2, height: 2),
            ] {
                #expect(
                    raster.maximumAlpha(inTopOriginRect: corner) < 0.01,
                    "\(name) should keep the \(corner) corner clear"
                )
            }
        }
    }

    @Test("Each mark's body resolves to the image branch, not the empty failure branch")
    func bodiesResolve() {
        let bodies: [any View] = [FirecrawlIcon().body, TavilyIcon().body, BraveIcon().body, ExaIcon().body]
        for body in bodies {
            let description = String(reflecting: type(of: body))
            #expect(description.contains("Image"), "the parsed mark should back the body")
            #expect(!description.contains("EmptyView"), "a failed parse must not pass silently")
        }
    }
}

private struct MarkRaster {
    let representation: NSBitmapImageRep
    let scale = 2

    init(image: NSImage) throws {
        representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(image.size.width) * scale,
                pixelsHigh: Int(image.size.height) * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        representation.size = image.size

        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
    }

    func maximumAlpha(inTopOriginRect rect: NSRect) -> CGFloat {
        let minimumX = max(0, Int((rect.minX * CGFloat(scale)).rounded(.down)))
        let maximumX = min(
            representation.pixelsWide,
            Int((rect.maxX * CGFloat(scale)).rounded(.up))
        )
        let minimumTopY = max(0, Int((rect.minY * CGFloat(scale)).rounded(.down)))
        let maximumTopY = min(
            representation.pixelsHigh,
            Int((rect.maxY * CGFloat(scale)).rounded(.up))
        )

        return (minimumX..<maximumX).reduce(CGFloat.zero) { xMaximum, x in
            (minimumTopY..<maximumTopY).reduce(xMaximum) { maximum, topY in
                let bitmapY = representation.pixelsHigh - 1 - topY
                let alpha = representation.colorAt(x: x, y: bitmapY)?.alphaComponent ?? 0
                return max(maximum, alpha)
            }
        }
    }
}
