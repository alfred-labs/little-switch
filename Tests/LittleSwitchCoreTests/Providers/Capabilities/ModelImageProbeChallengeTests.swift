import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import LittleSwitchCore

@Suite("Synthetic image probe challenge")
struct ModelImageProbeChallengeTests {
    @Test(
        "The PNG contains the expected quadrants, not a textual answer",
        arguments: zip(
            [["red", "green", "blue", "yellow"], ["white", "black", "yellow", "red"]],
            [
                [[UInt8(255), 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]],
                [[UInt8(255), 255, 255], [0, 0, 0], [255, 255, 0], [255, 0, 0]],
            ]))
    func imagePixels(colors: [String], expected: [[UInt8]]) throws {
        let challenge = try ModelImageProbeChallenge.make(colors: colors)
        let source = try #require(CGImageSourceCreateWithData(challenge.png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 256)
        #expect(image.height == 256)
        #expect(challenge.png.count < 4 * 1_024)
        #expect(challenge.expectedColors == colors)
        let bytes = try #require(image.dataProvider?.data) as Data
        let pixelBytes = image.bitsPerPixel / 8
        let centers = [(64, 64), (192, 64), (64, 192), (192, 192)]
        for (point, color) in zip(centers, expected) {
            let offset = point.1 * image.bytesPerRow + point.0 * pixelBytes
            #expect(Array(bytes[offset..<(offset + 3)]) == color)
        }
        let divider = 128 * image.bytesPerRow + 128 * pixelBytes
        #expect(Array(bytes[divider..<(divider + 3)]) == [128, 128, 128])
    }

    @Test("Invalid or degenerate palettes are not usable challenges")
    func palettes() throws {
        #expect(throws: (any Error).self) { try ModelImageProbeChallenge.make(colors: ["red"]) }
        #expect(throws: (any Error).self) { try ModelImageProbeChallenge.make(colors: ["red", "red", "red", "red"]) }
        #expect(throws: (any Error).self) {
            try ModelImageProbeChallenge.make(colors: ["red", "green", "blue", "purple"])
        }
        let random = try ModelImageProbeChallenge.make()
        #expect(random.expectedColors.count == 4)
        #expect(Set(random.expectedColors).count >= 3)
    }
}
