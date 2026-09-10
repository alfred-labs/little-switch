import Foundation
import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite("Server-sent event decoder")
struct ServerSentEventDecoderTests {
    @Test("CRLF frames survive every byte boundary")
    func byteByByteCRLFFrame() throws {
        let wire = Data(
            ("event: sample\r\n: \u{1F642}\r\n"
                + "unknown: ignored\r\ndata: first\r\ndata: second\r\n\r\n").utf8
        )
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 1_024)
        var frames: [ServerSentEventFrame] = []

        for byte in wire {
            frames += try decoder.append(ByteBuffer(bytes: [byte]))
        }
        frames += try decoder.finish()

        #expect(
            frames == [
                ServerSentEventFrame(
                    event: "sample",
                    data: Data("first\nsecond".utf8),
                    terminal: false
                )
            ]
        )
    }

    @Test("Random chunk boundaries never change the decoded frames")
    func randomChunkingMatchesSingleAppend() throws {
        let wire = Data(
            ("event: one\ndata: a\n\n"
                + "data: b\r\n\r\n"
                + "event: two\rdata: c\r"
                + ": comment\n\n"
                + "data: [DONE]\n\n"
                + "data: split-deferred\r"
                + "\ndata: tail\r\r").utf8
        )
        var oracle = ServerSentEventDecoder(maximumFrameBytes: 1_024)
        var expected = try oracle.append(ByteBuffer(bytes: [UInt8](wire)))
        expected += try oracle.finish()

        // A small deterministic generator keeps failures reproducible.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<100 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var decoder = ServerSentEventDecoder(maximumFrameBytes: 1_024)
            var decoded: [ServerSentEventFrame] = []
            var start = wire.startIndex
            while start < wire.endIndex {
                let span = 1 + Int((seed >> 33) % 7)
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let end = wire.index(start, offsetBy: span, limitedBy: wire.endIndex) ?? wire.endIndex
                decoded += try decoder.append(ByteBuffer(bytes: [UInt8](wire[start..<end])))
                start = end
            }
            decoded += try decoder.finish()
            #expect(decoded == expected)
        }
    }

    @Test("A large frame streamed in small chunks still decodes")
    func largeFrameInSmallChunks() throws {
        let body = String(repeating: "x", count: 400_000)
        let wire = Data("data: \(body)\n\n".utf8)
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 8 * 1_024 * 1_024)

        var frames: [ServerSentEventFrame] = []
        var start = wire.startIndex
        while start < wire.endIndex {
            let end = wire.index(start, offsetBy: 4_096, limitedBy: wire.endIndex) ?? wire.endIndex
            frames += try decoder.append(ByteBuffer(bytes: [UInt8](wire[start..<end])))
            start = end
        }
        frames += try decoder.finish()

        #expect(frames.map(\.data.count) == [400_000])
    }

    @Test(
        "CR-only and mixed line endings delimit consecutive frames",
        arguments: ["\r\r", "\r\n\n", "\n\r\n", "\r\r\n", "\r\n\r", "\n\r"]
    )
    func crAndMixedLineEndings(separator: String) throws {
        let wire = Data(
            ("event: sample\rdata: first\rdata: second"
                + separator
                + "data: next\n\n").utf8
        )
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 1_024)
        var frames: [ServerSentEventFrame] = []

        for byte in wire {
            frames += try decoder.append(ByteBuffer(bytes: [byte]))
        }
        frames += try decoder.finish()

        #expect(
            frames == [
                ServerSentEventFrame(
                    event: "sample",
                    data: Data("first\nsecond".utf8),
                    terminal: false
                ),
                ServerSentEventFrame(
                    event: nil,
                    data: Data("next".utf8),
                    terminal: false
                ),
            ]
        )
    }

    @Test("A deferred CR delimiter is completed at end of input")
    func deferredDelimiterAtEndOfInput() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        #expect(try decoder.append(ByteBuffer(string: "data: final\r\r")).isEmpty)
        #expect(
            try decoder.finish()
                == [
                    ServerSentEventFrame(
                        event: nil,
                        data: Data("final".utf8),
                        terminal: false
                    )
                ]
        )
    }

    @Test("A three-byte deferred delimiter is completed at end of input")
    func deferredThreeByteDelimiterAtEndOfInput() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        #expect(try decoder.append(ByteBuffer(string: "data: final\r\n\r")).isEmpty)
        #expect(
            try decoder.finish()
                == [
                    ServerSentEventFrame(
                        event: nil,
                        data: Data("final".utf8),
                        terminal: false
                    )
                ]
        )
    }

    @Test("A deferred delimiter closes within the same append")
    func deferredDelimiterClosedInSameAppend() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        #expect(
            try decoder.append(ByteBuffer(string: "data: a\n\rX"))
                == [
                    ServerSentEventFrame(
                        event: nil,
                        data: Data("a".utf8),
                        terminal: false
                    )
                ]
        )
    }

    @Test("A deferred comment-only delimiter yields no frame")
    func deferredCommentDelimiterAtEndOfInput() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        #expect(try decoder.append(ByteBuffer(string: ": keep-alive\r\r")).isEmpty)
        #expect(try decoder.finish().isEmpty)
    }

    @Test("Fields without a colon use an empty value")
    func fieldWithoutColon() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        #expect(
            try decoder.append(ByteBuffer(string: "event\ndata\n\n"))
                == [
                    ServerSentEventFrame(
                        event: "",
                        data: Data(),
                        terminal: false
                    )
                ]
        )
    }

    @Test("LF comments are ignored and DONE is terminal")
    func doneAndComments() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        let frames = try decoder.append(
            ByteBuffer(string: ": keep-alive\n\ndata: [DONE]\n\n")
        )

        #expect(
            frames == [
                ServerSentEventFrame(event: nil, data: Data(), terminal: true)
            ]
        )
        #expect(try decoder.finish().isEmpty)
    }

    @Test("Only the exact DONE marker is terminal", arguments: ["[DONE] ", "prefix[DONE]"])
    func doneNearNeighbors(data: String) throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)

        let frames = try decoder.append(ByteBuffer(string: "data: \(data)\n\n"))

        #expect(
            frames == [
                ServerSentEventFrame(
                    event: nil,
                    data: Data(data.utf8),
                    terminal: false
                )
            ]
        )
    }

    @Test("Incomplete frames fail at end of input")
    func incompleteFrame() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)
        _ = try decoder.append(ByteBuffer(string: "data: unfinished"))

        #expect(throws: ServerSentEventDecoder.Error.incompleteFrame) {
            _ = try decoder.finish()
        }
    }

    @Test("Invalid UTF-8 residue is distinguished at end of input")
    func invalidUTF8Residue() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)
        let residue = Array("data: ".utf8) + [0xFF]
        _ = try decoder.append(ByteBuffer(bytes: residue))

        #expect(throws: ServerSentEventDecoder.Error.invalidUTF8) {
            _ = try decoder.finish()
        }
    }

    @Test(
        "Frame limits exclude LF and CRLF separators",
        arguments: ["\n\n", "\r\n\r\n"]
    )
    func exactFrameLimit(separator: String) throws {
        let frame = "data: exact"
        let maximumFrameBytes = frame.utf8.count
        var accepted = ServerSentEventDecoder(maximumFrameBytes: maximumFrameBytes)

        #expect(
            try accepted.append(
                ByteBuffer(string: frame + String(separator.dropLast()))
            ).isEmpty
        )
        let frames = try accepted.append(
            ByteBuffer(string: String(separator.suffix(1)))
        )
        #expect(
            frames == [
                ServerSentEventFrame(
                    event: nil,
                    data: Data("exact".utf8),
                    terminal: false
                )
            ]
        )

        var rejected = ServerSentEventDecoder(maximumFrameBytes: maximumFrameBytes)
        #expect(throws: ServerSentEventDecoder.Error.frameTooLarge) {
            _ = try rejected.append(
                ByteBuffer(string: frame + "x" + separator)
            )
        }
    }

    @Test("Frames over the byte limit are rejected")
    func oversizedFrame() {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4)

        #expect(throws: ServerSentEventDecoder.Error.frameTooLarge) {
            _ = try decoder.append(ByteBuffer(string: "data: 12345\n\n"))
        }
    }

    @Test("Frames over the byte limit are rejected before any separator arrives")
    func oversizedFrameWithoutSeparator() {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4)

        #expect(throws: ServerSentEventDecoder.Error.frameTooLarge) {
            _ = try decoder.append(ByteBuffer(string: "data: 12345"))
        }
    }

    @Test("Complete frames must contain valid UTF-8")
    func invalidUTF8() {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)
        let wire = Array("data: ".utf8) + [0xFF, 0x0A, 0x0A]

        #expect(throws: ServerSentEventDecoder.Error.invalidUTF8) {
            _ = try decoder.append(ByteBuffer(bytes: wire))
        }
    }

    @Test("Trailing whitespace is accepted at end of input")
    func trailingWhitespace() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)
        _ = try decoder.append(ByteBuffer(string: " \t\r\n"))

        #expect(try decoder.finish().isEmpty)
    }
}
