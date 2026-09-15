import Foundation

/// Small RGB challenge, created entirely in memory with no textual PNG metadata.
enum ModelImageProbePNG {
    static func encode(colors: [ModelImageProbeColor]) throws -> Data {
        let palette = colors.map(\.rgb)
        var pixels = [UInt8](repeating: 255, count: 256 * 256 * 4)
        for y in 0..<256 {
            for x in 0..<256 {
                let color =
                    (124..<132).contains(x) || (124..<132).contains(y)
                    ? [UInt8(128), 128, 128]
                    : palette[(y / 128) * 2 + x / 128]
                let offset = (y * 256 + x) * 4
                pixels[offset] = color[0]
                pixels[offset + 1] = color[1]
                pixels[offset + 2] = color[2]
            }
        }
        return try ModelImageProbePNGEncoder.encode(pixels: Data(pixels), width: 256, height: 256)
    }
}
