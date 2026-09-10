import Foundation
import libzstd

func zstdCompressed(_ data: Data) throws -> Data {
    let capacity = ZSTD_compressBound(data.count)
    var compressed = Data(count: capacity)
    let count = compressed.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            ZSTD_compress(
                destination.baseAddress,
                destination.count,
                source.baseAddress,
                source.count,
                1
            )
        }
    }
    guard ZSTD_isError(count) == 0 else {
        throw ZstandardTestError.compressionFailed
    }
    compressed.removeSubrange(count..<compressed.count)
    return compressed
}

func zstdCompressedWithoutContentSize(_ data: Data) throws -> Data {
    guard let context = ZSTD_createCCtx() else {
        throw ZstandardTestError.compressionFailed
    }
    defer { ZSTD_freeCCtx(context) }
    guard ZSTD_isError(ZSTD_CCtx_setParameter(context, ZSTD_c_contentSizeFlag, 0)) == 0 else {
        throw ZstandardTestError.compressionFailed
    }

    let capacity = ZSTD_compressBound(data.count)
    var compressed = Data(count: capacity)
    let count = compressed.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            ZSTD_compress2(
                context,
                destination.baseAddress,
                destination.count,
                source.baseAddress,
                source.count
            )
        }
    }
    guard ZSTD_isError(count) == 0 else {
        throw ZstandardTestError.compressionFailed
    }
    compressed.removeSubrange(count..<compressed.count)
    return compressed
}

private enum ZstandardTestError: Swift.Error {
    case compressionFailed
}
