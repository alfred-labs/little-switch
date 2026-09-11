import Foundation
import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite("Server-sent event data rewriting")
struct ServerSentEventDataRewriterTests {
    @Test("Changing data preserves every non-data byte and line ending", arguments: ["\n", "\r\n", "\r"])
    func preservesMetadata(lineEnding: String) throws {
        let prefix = ": keep \u{1F642}\(lineEnding)id: 17\(lineEnding)event: sample\(lineEnding)"
        let suffix = "retry: 500\(lineEnding)x-field: untouched\(lineEnding)\(lineEnding)"
        let wire = Data((prefix + "data: old\(lineEnding)" + suffix).utf8)
        let frames = try decode(wire)
        let rewritten = try ServerSentEventDataRewriter.rewrite(wire, frames: frames) { _ in Data("new\nnext".utf8) }
        #expect(rewritten == Data((prefix + "data: new\(lineEnding)data: next\(lineEnding)" + suffix).utf8))
        #expect(try decode(rewritten).map(\.data) == [Data("new\nnext".utf8)])
    }

    @Test("Identical payload text inside an earlier comment never becomes the replacement target")
    func ignoresCommentSubstring() throws {
        let wire = Data(": data: old\n\ndata: old\n\n".utf8)
        let rewritten = try ServerSentEventDataRewriter.rewrite(wire, frames: decode(wire)) { _ in Data("new".utf8) }
        #expect(rewritten == Data(": data: old\n\ndata: new\n\n".utf8))
    }

    @Test("Replacing several data fields preserves interleaved metadata exactly")
    func interleavedFields() throws {
        let wire = Data("data\r\n: middle\rid:\ndata: old\rretry: 7\r\n\r\n".utf8)
        let rewritten = try ServerSentEventDataRewriter.rewrite(wire, frames: decode(wire)) { _ in Data("new".utf8) }
        #expect(rewritten == Data("data: new\r\n: middle\rid:\nretry: 7\r\n\r\n".utf8))
    }

    @Test("Unchanged payloads and terminal frames retain all original formatting")
    func unchangedFrames() throws {
        let wire = Data(": keep\r\ndata: old\r\n\r\ndata: [DONE]\n\n \t".utf8)
        var called = 0
        let rewritten = try ServerSentEventDataRewriter.rewrite(wire, frames: decode(wire)) { value in
            called += 1
            return value
        }
        #expect(rewritten == wire)
        #expect(called == 1)
    }

    @Test("Transforms fail closed without valid source metadata or valid UTF-8")
    func invalidSourceAndTransform() throws {
        let wire = Data("data: old\n\n".utf8)
        let missing = ServerSentEventFrame(event: nil, data: Data("old".utf8), terminal: false)
        #expect(throws: ServerSentEventDataRewriter.Error.self) {
            try ServerSentEventDataRewriter.rewrite(wire, frames: [missing]) { _ in Data("new".utf8) }
        }
        #expect(throws: ServerSentEventDataRewriter.Error.self) {
            try ServerSentEventDataRewriter.rewrite(wire, frames: decode(wire)) { _ in Data([0xFF]) }
        }
        #expect(throws: ServerSentEventDataRewriter.Error.invalidData) {
            try ServerSentEventDataRewriter.rewrite(wire, frames: decode(wire)) { _ in Data("new\rid: injected".utf8) }
        }
        #expect(throws: ServerSentEventDecoder.Error.incompleteFrame) {
            try ServerSentEventDataRewriter.rewrite(wire, frames: decode(wire)) { _ in
                throw ServerSentEventDecoder.Error.incompleteFrame
            }
        }
    }

    @Test("Source formatting is retained without changing logical frame equality")
    func sourceFormattingIsMetadata() throws {
        let wire = Data(": comment\r\ndata: value\r\n\r\n".utf8)
        let frame = try #require(try decode(wire).first)
        #expect(frame.sourceData == Data(": comment\r\ndata: value".utf8))
        #expect(frame.sourceRange == 0..<wire.count)
        #expect(frame == ServerSentEventFrame(event: nil, data: Data("value".utf8), terminal: false))
    }

    @Test("Absolute source ranges survive every chunk boundary and deferred EOF separators")
    func sourceRangesAcrossChunks() throws {
        let prefix = Data(": ignored\r\r".utf8)
        let first = Data("data: first\n\n".utf8)
        let terminal = Data("data: [DONE]\r\n\r".utf8)
        let wire = prefix + first + terminal
        for split in 0...wire.count {
            var decoder = ServerSentEventDecoder(maximumFrameBytes: 64)
            let frames =
                try decoder.append(ByteBuffer(bytes: wire.prefix(split)))
                + decoder.append(ByteBuffer(bytes: wire.dropFirst(split))) + decoder.finish()
            #expect(
                frames.map(\.sourceRange) == [
                    prefix.count..<(prefix.count + first.count), (prefix.count + first.count)..<wire.count,
                ])
            #expect(frames.map(\.sourceData) == [Data("data: first".utf8), Data("data: [DONE]".utf8)])
            #expect(frames.last?.terminal == true)
            #expect(decoder.consumedBytes == wire.count)
        }
    }

    @Test("Rewriting a retained stream slice uses its absolute offset and its actual Data indices")
    func offsetSlice() throws {
        let prefix = Data(": ignored\n\n".utf8)
        let kept = Data("data: keep\n\n".utf8)
        let changed = Data("data: old\r\n\r\n".utf8)
        let terminal = Data("data: [DONE]\r\r".utf8)
        let wire = prefix + kept + changed + terminal
        let slice = wire.dropFirst(prefix.count)
        let result = try ServerSentEventDataRewriter.rewrite(slice, sourceOffset: prefix.count, frames: decode(wire)) {
            $0 == Data("old".utf8) ? Data("new".utf8) : $0
        }
        #expect(result == kept + Data("data: new\r\n\r\n".utf8) + terminal)
    }

    @Test(
        "Multiline and empty replacements preserve all separator variants",
        arguments: ["\n\n", "\r\r", "\n\r", "\r\n\r", "\r\r\n", "\n\r\n", "\r\n\n", "\r\n\r\n"])
    func replacementSeparator(separator: String) throws {
        let wire = Data(("data: old" + separator).utf8)
        let frames = try decode(wire)
        let ending = separator.hasPrefix("\r\n") ? "\r\n" : String(separator.prefix(1))
        let multiline = try ServerSentEventDataRewriter.rewrite(wire, frames: frames) { _ in Data("new\nnext\n".utf8) }
        #expect(multiline == Data("data: new\(ending)data: next\(ending)data: \(separator)".utf8))
        #expect(try decode(multiline).map(\.data) == [Data("new\nnext\n".utf8)])
        let empty = try ServerSentEventDataRewriter.rewrite(wire, frames: frames) { _ in Data() }
        #expect(empty == Data(("data: " + separator).utf8))
        #expect(try decode(empty).map(\.data) == [Data()])
    }

    @Test("Invalid or overlapping source metadata fails without searching for another occurrence")
    func invalidMetadata() throws {
        let wire = Data("data: old\n\n".utf8)
        let original = try #require(try decode(wire).first)
        var variants = [ServerSentEventFrame]()
        var missingRange = original
        missingRange.sourceRange = nil
        variants.append(missingRange)
        var pastEnd = original
        pastEnd.sourceRange = 0..<(wire.count + 1)
        variants.append(pastEnd)
        var oversized = original
        oversized.sourceData = wire + wire
        variants.append(oversized)
        var mismatch = original
        mismatch.sourceData = Data("data: bad".utf8)
        variants.append(mismatch)
        for frame in variants {
            #expect(throws: ServerSentEventDataRewriter.Error.missingSource) {
                try ServerSentEventDataRewriter.rewrite(wire, frames: [frame]) { _ in Data("new".utf8) }
            }
        }
        for offset in [-1, 1] {
            #expect(throws: ServerSentEventDataRewriter.Error.missingSource) {
                try ServerSentEventDataRewriter.rewrite(wire, sourceOffset: offset, frames: [original]) { _ in
                    Data("new".utf8)
                }
            }
        }
        #expect(throws: ServerSentEventDataRewriter.Error.missingSource) {
            try ServerSentEventDataRewriter.rewrite(wire, frames: [original, original]) { _ in Data("new".utf8) }
        }
        #expect(throws: ServerSentEventDataRewriter.Error.missingSource) {
            try ServerSentEventDataRewriter.rewrite(Data("data: oldxx".utf8), frames: [original]) { _ in
                Data("new".utf8)
            }
        }
        var noField = original
        noField.sourceData = Data(": comment".utf8)
        #expect(throws: ServerSentEventDataRewriter.Error.missingSource) {
            try ServerSentEventDataRewriter.rewrite(Data(": comment\n\n".utf8), frames: [noField]) { _ in
                Data("new".utf8)
            }
        }
    }

    private func decode(_ bytes: Data) throws -> [ServerSentEventFrame] {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4_096)
        return try decoder.append(ByteBuffer(bytes: bytes)) + decoder.finish()
    }
}
