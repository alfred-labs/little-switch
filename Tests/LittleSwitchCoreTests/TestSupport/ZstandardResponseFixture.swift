import Foundation
import libzstd

/// Gateway integration fixtures encode an upstream body independently of the decoder.
func zstdCompressed(_ data: Data) throws -> Data {
    let capacity = ZSTD_compressBound(data.count)
    var compressed = Data(count: capacity)
    let count = compressed.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            ZSTD_compress(destination.baseAddress, destination.count, source.baseAddress, source.count, 1)
        }
    }
    guard ZSTD_isError(count) == 0 else {
        throw ZstandardFixtureError.compressionFailed
    }
    compressed.removeSubrange(count..<compressed.count)
    return compressed
}

private enum ZstandardFixtureError: Swift.Error {
    case compressionFailed
}
