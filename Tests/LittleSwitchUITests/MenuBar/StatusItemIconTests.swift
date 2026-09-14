import AppKit
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Status item icon")
@MainActor
struct StatusItemIconTests {
    @Test("The approved resting geometry remains exact")
    func idleGeometry() {
        #expect(
            StatusItemIcon.geometry(for: .idle)
                == StatusItemIconGeometry(
                    size: NSSize(width: 18, height: 18),
                    strokeWidth: 1,
                    cornerRadius: 3.75,
                    indicatorRadius: 1.75,
                    modules: [
                        StatusItemIconGeometry.Module(
                            bounds: NSRect(x: 0.5, y: 0.5, width: 7.5, height: 15),
                            style: .filled,
                            indicatorCenter: NSPoint(x: 4.25, y: 4.25)
                        ),
                        StatusItemIconGeometry.Module(
                            bounds: NSRect(x: 10, y: 2.5, width: 7.5, height: 15),
                            style: .outlined,
                            indicatorCenter: NSPoint(x: 13.75, y: 13.75)
                        ),
                    ]
                )
        )
    }

    @Test("The approved switched-on geometry remains exact")
    func activeGeometry() {
        #expect(
            StatusItemIcon.geometry(for: .active)
                == StatusItemIconGeometry(
                    size: NSSize(width: 18, height: 18),
                    strokeWidth: 1,
                    cornerRadius: 3.75,
                    indicatorRadius: 1.75,
                    modules: [
                        StatusItemIconGeometry.Module(
                            bounds: NSRect(x: 0.5, y: 0.5, width: 7.5, height: 15),
                            style: .outlined,
                            indicatorCenter: NSPoint(x: 4.25, y: 4.25)
                        ),
                        StatusItemIconGeometry.Module(
                            bounds: NSRect(x: 10, y: 2.5, width: 7.5, height: 15),
                            style: .filled,
                            indicatorCenter: NSPoint(x: 13.75, y: 13.75)
                        ),
                    ]
                )
        )
    }

    @Test("Switching on moves the fill and nothing else")
    func theFillTravels() {
        let idle = StatusItemIcon.geometry(for: .idle).modules
        let active = StatusItemIcon.geometry(for: .active).modules

        #expect(idle.map(\.bounds) == active.map(\.bounds))
        #expect(idle.map(\.indicatorCenter) == active.map(\.indicatorCenter))
        #expect(idle.map(\.style) == [.filled, .outlined])
        #expect(active.map(\.style) == [.outlined, .filled])
    }

    @Test(
        "Both states are 18 point template images",
        arguments: [StatusItemIconState.idle, .active]
    )
    func templateImage(state: StatusItemIconState) {
        let image = StatusItemIcon.makeImage(for: state)

        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
    }

    @Test(
        "Each state rasterises its own motif",
        arguments: [StatusItemIconState.idle, .active]
    )
    func templateRaster(state: StatusItemIconState) throws {
        let image = StatusItemIcon.makeImage(for: state)
        let expectation = RasterExpectation.approved(for: state)

        for scale in [1, 2] {
            let raster = try AlphaRaster(image: image, scale: scale)

            for occupiedRegion in expectation.occupied {
                #expect(raster.maximumAlpha(inTopOriginRect: occupiedRegion) > 0.1)
            }

            for clearRegion in expectation.clear {
                #expect(raster.maximumAlpha(inTopOriginRect: clearRegion) < 0.01)
            }
        }

        // Hairline negative space — the knocked-out indicator and the open gap
        // — is only whole pixels at 2x. At 1x a single pixel straddles those
        // edges and keeps a little alpha, which is antialiasing, not ink.
        let retina = try AlphaRaster(image: image, scale: 2)
        for clearRegion in expectation.clearOnRetina {
            #expect(retina.maximumAlpha(inTopOriginRect: clearRegion) < 0.01)
        }
    }

    @Test("The status item follows the model and preserves accessibility")
    func statusItemIntegration() throws {
        let source = try repositorySource("Sources/LittleSwitchUI/MenuBar/StatusItemVisibilityRecovery.swift")

        #expect(source.contains("StatusItemIcon.makeImage(for: iconState)"))
        #expect(source.contains("StatusItemIcon.makeImage(for: state)"))
        #expect(source.contains("model.statusItemIconState"))
        // The glyph is rebuilt only when the state it reports changes.
        #expect(source.contains("guard state != lastRenderedIconState else {"))
        #expect(!source.contains("arrow.triangle.swap"))
        #expect(source.contains("setAccessibilityLabel(\"LittleSwitch\")"))
        #expect(source.contains("toolTip = \"LittleSwitch\""))

        let polling = try repositorySource(
            "Sources/LittleSwitchUI/Features/Activity/LittleSwitchApplicationDelegateGatewayActivity.swift"
        )
        #expect(polling.contains("statusItemController?.refreshIcon()"))
    }

    @Test("A switched application is what turns the glyph on")
    func iconStateFollowsSwitches() {
        #expect(Self.model().statusItemIconState == .idle)
        #expect(Self.model(claudeConnected: true).statusItemIconState == .active)
        #expect(Self.model(codexConnected: true).statusItemIconState == .active)
        #expect(Self.model(claudeCode: .connected).statusItemIconState == .active)
        #expect(Self.model(openCode: .connected).statusItemIconState == .active)
        // A switch left on with a warning still routes through LittleSwitch.
        #expect(Self.model(claudeCode: .needsAttention).statusItemIconState == .active)
        #expect(Self.model(openCode: .recoveryAvailable).statusItemIconState == .active)
        // An unrecoverable switch is off, whatever else it reports.
        #expect(Self.model(claudeCode: .recoveryUnavailable).statusItemIconState == .idle)
        #expect(Self.model(openCode: .recoveryUnavailable).statusItemIconState == .idle)
    }

    private static func model(
        claudeConnected: Bool = false,
        codexConnected: Bool = false,
        claudeCode: ClaudeCodeConnectionStatus = .disconnected,
        openCode: OpenCodeConnectionStatus = .disconnected
    ) -> AppModel {
        AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(
                    connected: claudeConnected,
                    codex: CodexConfiguration(connected: codexConnected)
                ),
                claudeCodeStatus: claudeCode,
                openCodeStatus: openCode
            )
        )
    }

    private func repositorySource(_ path: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

/// Where each state must and must not put ink. Regions are top-origin points
/// on the 18-point canvas, the same convention as the geometry itself.
private struct RasterExpectation {
    let occupied: [NSRect]
    let clear: [NSRect]
    let clearOnRetina: [NSRect]

    static func approved(for state: StatusItemIconState) -> RasterExpectation {
        switch state {
        case .idle:
            RasterExpectation(
                occupied: [leftCore, leftCap, rightCap, rightIndicator],
                clear: outsideTheModules + [rightCore],
                clearOnRetina: [leftIndicator, gap]
            )
        case .active:
            RasterExpectation(
                occupied: [rightCore, rightCap, leftCap, leftIndicator],
                clear: outsideTheModules + [leftCore],
                clearOnRetina: [rightIndicator, gap]
            )
        }
    }

    /// The heart of each capsule: solid in the module the fill sits in, empty
    /// in the other one. This pair alone tells the two states apart.
    private static let leftCore = NSRect(x: 3, y: 8, width: 3, height: 3)
    private static let rightCore = NSRect(x: 12, y: 8, width: 3, height: 3)

    /// The end each capsule is drawn from, whichever style it carries.
    private static let leftCap = NSRect(x: 3, y: 0.5, width: 2, height: 1)
    private static let rightCap = NSRect(x: 12.5, y: 2.5, width: 2, height: 1)

    /// Ink when the indicator is filled inside an outlined module, a hole when
    /// it is knocked out of a filled one.
    private static let leftIndicator = NSRect(x: 3.5, y: 3.5, width: 1.5, height: 1.5)
    private static let rightIndicator = NSRect(x: 13, y: 13, width: 1.5, height: 1.5)

    /// The modules never touch, in either state.
    private static let gap = NSRect(x: 8.5, y: 8, width: 1, height: 2)

    private static let outsideTheModules =
        corners + [
            // The right module sits lower than the left one, in both states.
            NSRect(x: 11, y: 0.5, width: 5, height: 1),
            NSRect(x: 2, y: 16.5, width: 5, height: 1),
        ]

    private static let corners = [
        NSRect(x: 0, y: 0, width: 0.5, height: 0.5),
        NSRect(x: 17.5, y: 0, width: 0.5, height: 0.5),
        NSRect(x: 0, y: 17.5, width: 0.5, height: 0.5),
        NSRect(x: 17.5, y: 17.5, width: 0.5, height: 0.5),
    ]
}

private struct AlphaRaster {
    let representation: NSBitmapImageRep
    let scale: Int

    init(image: NSImage, scale: Int) throws {
        self.scale = scale
        let width = Int(image.size.width) * scale
        let height = Int(image.size.height) * scale
        representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
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
                // colorAt's own origin is the bitmap's top-left pixel.
                let alpha = representation.colorAt(x: x, y: topY)?.alphaComponent ?? 0
                return max(maximum, alpha)
            }
        }
    }
}
