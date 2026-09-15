import CoreGraphics
import Foundation
import ImageIO

/// Small RGB challenge, created entirely in memory with no textual PNG metadata.
enum ModelImageProbePNG {
    static func encode(colors: [String]) throws -> Data {
        let palette: [String: [UInt8]] = [
            "red": [255, 0, 0], "green": [0, 255, 0], "blue": [0, 0, 255],
            "yellow": [255, 255, 0], "black": [0, 0, 0], "white": [255, 255, 255],
        ]
        var pixels = [UInt8](repeating: 255, count: 256 * 256 * 4)
        for y in 0..<256 {
            for x in 0..<256 {
                let color =
                    (124..<132).contains(x) || (124..<132).contains(y)
                    ? [UInt8(128), 128, 128]
                    : palette[colors[(y / 128) * 2 + x / 128], default: [0, 0, 0]]
                let offset = (y * 256 + x) * 4
                pixels[offset] = color[0]
                pixels[offset + 1] = color[1]
                pixels[offset + 2] = color[2]
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: 256,
                height: 256,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 256 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder32Big),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent)
        else { throw ModelImageProbeChallenge.Error.imageEncoding }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ModelImageProbeChallenge.Error.imageEncoding
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ModelImageProbeChallenge.Error.imageEncoding }
        return data as Data
    }
}
