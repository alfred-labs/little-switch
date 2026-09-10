import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

@Suite("Transport decompression")
struct HTTPTransportDecompressionTests {
    /// A real gzip payload of `String(repeating: "decompressed-body-", count: 64)`.
    /// Precomputed to avoid depending on the Compression framework in tests;
    /// the exact bytes are irrelevant as long as they are valid gzip.
    private static let compressedBody = Data([
        0x1F, 0x8B, 0x08, 0x00, 0x4A, 0x89, 0xA2, 0x6A, 0x02, 0xFF, 0x4B, 0x49,
        0x4D, 0xCE, 0xCF, 0x2D, 0x28, 0x4A, 0x2D, 0x2E, 0x4E, 0x4D, 0xD1, 0x4D,
        0xCA, 0x4F, 0xA9, 0xD4, 0x4D, 0x19, 0x15, 0x19, 0x15, 0x19, 0x15, 0x19,
        0x15, 0xA1, 0x8B, 0x08, 0x00, 0xE5, 0xCB, 0x5C, 0x37, 0x80, 0x04, 0x00,
        0x00,
    ])
    private static let decompressedBody = Data(String(repeating: "decompressed-body-", count: 64).utf8)

    @Test("Live transport decompresses a gzip response over a loopback connection")
    func liveDecompression() async throws {
        let server = try LoopbackHTTPServer(
            statusCode: 200, contentType: "application/octet-stream", body: Self.compressedBody)
        try await server.start()
        defer { Task { await server.stop() } }
        let port = try #require(server.port)

        let transport = AsyncHTTPTransport()
        defer { Task { try? await transport.shutdown() } }
        var request = HTTPClientRequest(url: "http://127.0.0.1:\(port)/")
        request.headers.add(name: "accept-encoding", value: "gzip")
        let response = try await transport.execute(request)
        #expect(response.status == .ok)
        let received = try await Self.read(response.body)
        #expect(Data(received) == Self.decompressedBody)
    }

    private static func read(_ body: HTTPClientResponse.Body) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        for try await chunk in body { bytes.append(contentsOf: chunk.readableBytesView) }
        return bytes
    }
}
