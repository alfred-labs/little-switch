import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("OTLP HTTP bounds and cancellation")
struct OTLPHTTPBoundaryTests {
    @Test("The response limit applies after gzip decompression")
    func decompressedLimit() async throws {
        let compressed = try #require(Data(base64Encoded: "H4sIAAAAAAAC/3N0HAWjYBQMdwAAAS6gUegDAAA="))
        #expect(compressed.count < 64)
        let router = Router()
        router.post("/compressed") { _, _ in
            Response(
                status: .ok,
                headers: [.contentEncoding: "gzip"],
                body: .init(byteBuffer: ByteBuffer(bytes: compressed))
            )
        }
        try await Application(router: router).test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/compressed"))
            let transport = OTLPHTTPTransport(maximumResponseBytes: 64)
            await #expect(throws: OTLPHTTPTransport.Failure.responseTooLarge) {
                _ = try await transport.send(to: endpoint, body: Data(), bearer: nil)
            }
            await transport.shutdown()
        }
    }

    @Test("Invalid credentials and pre-cancelled sends fail before any connection")
    func beforeNetwork() async throws {
        let transport = OTLPHTTPTransport()
        let endpoint = try #require(URL(string: "http://localhost:1/unused"))
        for token in ["", "space in token", "line\nbreak", "é"] {
            await #expect(throws: OTLPHTTPTransport.Failure.invalidCredential) {
                _ = try await transport.send(to: endpoint, body: Data(), bearer: token)
            }
        }
        let gate = AsyncTestGate()
        let task = Task {
            do { try await gate.wait() } catch {}
            return try await transport.send(to: endpoint, body: Data(), bearer: nil)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await transport.shutdown()
    }
}
