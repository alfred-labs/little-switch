import Foundation
import Testing

@testable import LittleSwitchTransport

@Suite("Zstandard request decoding")
struct ZstandardTests {
    @Test("A zstd frame round-trips within the expanded body limit")
    func roundTrip() throws {
        let original = Data(#"{"model":"local","input":"hello"}"#.utf8)
        let compressed = try zstdCompressed(original)

        #expect(try Zstandard.decompress(compressed, maximumOutputBytes: 1_024) == original)
    }

    @Test("Invalid frames and expanded bodies over the limit are rejected")
    func invalidAndOversized() throws {
        #expect(throws: Zstandard.Error.outputTooLarge) {
            try Zstandard.decompress(Data(), maximumOutputBytes: -1)
        }
        #expect(throws: Zstandard.Error.invalidFrame) {
            try Zstandard.decompress(Data("not-zstd".utf8), maximumOutputBytes: 1_024)
        }

        let compressed = try zstdCompressed(Data(repeating: 65, count: 4_096))
        #expect(throws: Zstandard.Error.outputTooLarge) {
            try Zstandard.decompress(compressed, maximumOutputBytes: 64)
        }
    }

    @Test("Known-size frames decode at the exact output boundary")
    func exactKnownBoundary() throws {
        let original = Data(repeating: 65, count: 128)
        let compressed = try zstdCompressed(original)

        #expect(try Zstandard.decompress(compressed, maximumOutputBytes: original.count) == original)
    }

    @Test("Unknown-size frames enforce overflow and destination boundaries")
    func unknownSizeBoundaries() throws {
        let original = Data(repeating: 65, count: 128)
        let compressed = try zstdCompressedWithoutContentSize(original)

        #expect(try Zstandard.decompress(compressed, maximumOutputBytes: original.count) == original)
        #expect(throws: Zstandard.Error.outputTooLarge) {
            try Zstandard.decompress(compressed, maximumOutputBytes: original.count - 1)
        }
        #expect(throws: Zstandard.Error.outputTooLarge) {
            try Zstandard.decompress(compressed, maximumOutputBytes: original.count - 2)
        }
        #expect(throws: Zstandard.Error.outputTooLarge) {
            try Zstandard.decompress(compressed, maximumOutputBytes: Int.max)
        }
    }

    @Test("A truncated frame with a valid header is rejected during decode")
    func corruptDecode() throws {
        let compressed = try zstdCompressed(Data(repeating: 65, count: 128))
        let truncated = Data(compressed.dropLast())

        #expect(throws: Zstandard.Error.invalidFrame) {
            try Zstandard.decompress(truncated, maximumOutputBytes: 128)
        }
    }
}
