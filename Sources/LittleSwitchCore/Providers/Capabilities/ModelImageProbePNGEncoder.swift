import CoreGraphics
import Foundation
import ImageIO

/// ImageIO boundary for an in-memory RGB raster; failures remain recoverable probe errors.
enum ModelImageProbePNGEncoder {
    static func encode(pixels: Data, width: Int, height: Int) throws -> Data {
        guard let provider = CGDataProvider(data: pixels as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
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
