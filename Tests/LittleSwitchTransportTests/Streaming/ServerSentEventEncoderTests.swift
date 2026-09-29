import Foundation
import NIOCore
import Testing

@testable import LittleSwitchTransport

struct ServerSentEventEncoderTests {
    @Test(
        "SSE framing preserves UTF-8 data, empty lines and trailing line breaks",
        arguments: [
            ("", "data: \n\n"),
            ("value", "data: value\n\n"),
            ("first\n\nlast\n", "data: first\ndata: \ndata: last\ndata: \n\n"),
            ("café 🦋", "data: café 🦋\n\n"),
            (
                #"{"opaque":9007199254740993,"text":"a\nb"}"#,
                #"data: {"opaque":9007199254740993,"text":"a\nb"}"# + "\n\n"
            ),
        ])
    func framesData(payload: String, expected: String) throws {
        let data = Data(payload.utf8)
        let encoded = try ServerSentEventEncoder.encode(data: data)
        #expect(encoded == Data(expected.utf8))
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 4_096)
        let decoded = try decoder.append(ByteBuffer(bytes: encoded)) + decoder.finish()
        #expect(decoded == [ServerSentEventFrame(event: nil, data: data, terminal: false)])
    }

    @Test(
        "SSE data cannot introduce fields through raw CR or invalid UTF-8",
        arguments: [Data([0xFF]), Data("a\rid: injected".utf8)])
    func rejectsUnrepresentableData(data: Data) {
        #expect(throws: ServerSentEventEncoder.Error.invalidData) {
            try ServerSentEventEncoder.encode(data: data)
        }
    }
}
