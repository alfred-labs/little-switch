import Foundation
import libzstd

public enum Zstandard {
    public enum Error: Swift.Error, Equatable {
        case invalidFrame
        case outputTooLarge
    }

    public static func decompress(
        _ data: Data,
        maximumOutputBytes: Int
    ) throws -> Data {
        guard maximumOutputBytes >= 0 else {
            throw Error.outputTooLarge
        }
        let frameSize = data.withUnsafeBytes { source in
            ZSTD_getFrameContentSize(source.baseAddress, source.count)
        }
        guard frameSize != ZSTD_CONTENTSIZE_ERROR else {
            throw Error.invalidFrame
        }
        let knownFrameIsTooLarge =
            frameSize != ZSTD_CONTENTSIZE_UNKNOWN
            && frameSize > UInt64(maximumOutputBytes)
        if knownFrameIsTooLarge {
            throw Error.outputTooLarge
        }

        let capacity: Int
        if frameSize == ZSTD_CONTENTSIZE_UNKNOWN {
            let expanded = maximumOutputBytes.addingReportingOverflow(1)
            guard !expanded.overflow else {
                throw Error.outputTooLarge
            }
            capacity = expanded.partialValue
        } else {
            capacity = Int(frameSize)
        }
        var output = Data(count: capacity)
        let result = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                ZSTD_decompress(
                    destination.baseAddress,
                    destination.count,
                    source.baseAddress,
                    source.count
                )
            }
        }
        if ZSTD_isError(result) != 0 {
            if ZSTD_getErrorCode(result) == ZSTD_error_dstSize_tooSmall {
                throw Error.outputTooLarge
            }
            throw Error.invalidFrame
        }
        guard result <= maximumOutputBytes else {
            throw Error.outputTooLarge
        }
        output.removeSubrange(result..<output.count)
        return output
    }
}
