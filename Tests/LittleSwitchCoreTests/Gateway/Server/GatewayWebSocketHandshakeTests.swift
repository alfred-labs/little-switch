import Foundation
import HTTPTypes
import HummingbirdWebSocket
import Logging
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket handshake")
struct GatewayWebSocketHandshakeTests {
    @Test("A valid loopback Responses handshake accepts token lists and a query")
    func acceptsResponsesHandshake() {
        let policy = GatewayWebSocketHandshakePolicy(requiredAuthorityPort: 11_436)
        var request = validRequest()
        request.path = "/v1/responses?client=codex"
        request.headerFields[.connection] = "keep-alive, UpGrAdE"
        request.headerFields[.upgrade] = "h2c, WebSocket"
        #expect(policy.allows(request))
    }

    @Test("Only the Responses GET endpoint can upgrade")
    func rejectsOtherRoutesAndMethods() {
        let policy = GatewayWebSocketHandshakePolicy(requiredAuthorityPort: 11_436)
        for path in ["/v1/messages", "/v1/responses/", "/v1/models", "/api/about", ""] {
            var request = validRequest()
            request.path = path
            #expect(!policy.allows(request))
        }
        var request = validRequest()
        request.method = .post
        #expect(!policy.allows(request))
        request.method = .get
        request.path = nil
        #expect(!policy.allows(request))
    }

    @Test("Origins and non-loopback or wrong-port authorities never upgrade")
    func enforcesGatewayAuthorityBoundary() {
        let policy = GatewayWebSocketHandshakePolicy(requiredAuthorityPort: 11_436)
        for authority in [nil, "localhost", "localhost:11437", "example.com:11436", "127.0.0.1.example.com:11436"] {
            var request = validRequest()
            request.authority = authority
            #expect(!policy.allows(request))
        }
        for origin in ["", "null", "http://localhost:11436", "https://example.com"] {
            var request = validRequest()
            request.headerFields[.origin] = origin
            #expect(!policy.allows(request))
        }
    }

    @Test("Upgrade requires the Connection token, version 13 and one valid 16-byte key")
    func rejectsMalformedHandshake() {
        let policy = GatewayWebSocketHandshakePolicy(requiredAuthorityPort: 11_436)
        let invalidFields: [(HTTPField.Name, String?)] = [
            (.connection, nil),
            (.connection, "keep-alive"),
            (.upgrade, nil),
            (.upgrade, "h2c"),
            (.secWebSocketVersion, nil),
            (.secWebSocketVersion, "12"),
            (.secWebSocketKey, nil),
            (.secWebSocketKey, "not-base64"),
            (.secWebSocketKey, "YQ=="),
            (.secWebSocketKey, ""),
        ]
        for (name, value) in invalidFields {
            var request = validRequest()
            request.headerFields[name] = value
            #expect(!policy.allows(request))
        }
        var request = validRequest()
        request.headerFields.append(.init(name: .secWebSocketKey, value: "dGhlIHNhbXBsZSBub25jZQ=="))
        #expect(!policy.allows(request))
    }

    @Test("WebSocket logging never enables frame payload traces")
    func payloadLoggingIsDisabled() {
        var logger = Logger(label: "websocket-privacy-test")
        logger.logLevel = .trace
        #expect(GatewayWebSocketChannel.metadataLogger(logger).logLevel == .info)
        logger.logLevel = .error
        #expect(GatewayWebSocketChannel.metadataLogger(logger).logLevel == .error)
    }

    @Test("WebSocket messages preserve UTF8 bytes and enforce their completed size")
    func messageBoundary() throws {
        #expect(try GatewayWebSocketServer.messageData(.text("é"), maximumBytes: 2) == Data([0xC3, 0xA9]))
        #expect(throws: GatewayWebSocketServer.MessageError.tooLarge) {
            try GatewayWebSocketServer.messageData(.text("é"), maximumBytes: 1)
        }
        #expect(throws: GatewayWebSocketServer.MessageError.binary) {
            try GatewayWebSocketServer.messageData(.binary(ByteBuffer(string: "{}")), maximumBytes: 2)
        }
        #expect(try GatewayWebSocketServer.responseText(Data([0xC3, 0xA9])) == "é")
        #expect(throws: GatewayWebSocketServer.MessageError.invalidText) {
            try GatewayWebSocketServer.responseText(Data([0xFF]))
        }
    }

    @Test("Accepted text reaches the session without a close frame")
    func receivesText() async throws {
        let data = try await GatewayWebSocketServer.receiveMessage(.text("é"), maximumBytes: 2) { _, _ in
            Issue.record("Accepted text must not close the WebSocket")
        }
        #expect(data == Data([0xC3, 0xA9]))
    }

    @Test("Completed oversize text closes with 1009 before rejecting the message")
    func rejectsCompletedOversizeText() async {
        let recorder = CloseRecorder()
        await #expect(throws: GatewayWebSocketServer.MessageError.tooLarge) {
            try await GatewayWebSocketServer.receiveMessage(.text("é"), maximumBytes: 1) { code, reason in
                await recorder.record(code, reason: reason)
            }
        }
        #expect(await recorder.frames == [.init(code: 1_009, reason: "Message is too large")])
    }

    @Test("Binary messages close with 1003 before rejecting the message")
    func rejectsBinaryMessage() async {
        let recorder = CloseRecorder()
        let message = WebSocketMessage.binary(ByteBuffer(string: "{}"))
        await #expect(throws: GatewayWebSocketServer.MessageError.binary) {
            try await GatewayWebSocketServer.receiveMessage(message, maximumBytes: 2) { code, reason in
                await recorder.record(code, reason: reason)
            }
        }
        #expect(await recorder.frames == [.init(code: 1_003, reason: "Text messages are required")])
    }

    @Test("A failed close write propagates out of message rejection", arguments: [false, true])
    func propagatesCloseWriteFailure(binary: Bool) async {
        let message: WebSocketMessage = binary ? .binary(ByteBuffer(string: "{}")) : .text("é")
        await #expect(throws: CloseWriteError.failed) {
            try await GatewayWebSocketServer.receiveMessage(message, maximumBytes: 1) { _, _ in
                throw CloseWriteError.failed
            }
        }
    }

    private enum CloseWriteError: Error {
        case failed
    }

    private actor CloseRecorder {
        struct Frame: Equatable {
            var code: UInt16
            var reason: String
        }

        private(set) var frames: [Frame] = []

        func record(_ code: WebSocketErrorCode, reason: String) {
            frames.append(.init(code: UInt16(webSocketErrorCode: code), reason: reason))
        }
    }

    private func validRequest() -> HTTPRequest {
        HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:11436",
            path: "/v1/responses",
            headerFields: [
                .connection: "Upgrade",
                .upgrade: "websocket",
                .secWebSocketVersion: "13",
                .secWebSocketKey: "dGhlIHNhbXBsZSBub25jZQ==",
            ]
        )
    }
}
