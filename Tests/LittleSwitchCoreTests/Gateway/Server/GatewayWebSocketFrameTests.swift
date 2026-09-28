import Foundation
import HummingbirdTesting
import LittleSwitchWire
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A fragmented message exceeding the aggregate limit closes with message-too-big")
    func responsesWebSocketRejectsOversizedFragmentedMessage() async throws {
        let fixture = try makeFixture()
        var limits = ResponsesWebSocketLimits()
        limits.maxFrameBytes = 16
        let app = try makeWebSocketApplication(fixture: fixture, limits: limits)
        try await app.test(.ahc()) { client in
            let port = try #require(client.port)
            let code = try await rawWebSocketCloseCode(
                port: port,
                frames: [
                    maskedFrame(opcode: .text, bytes: Array(repeating: 0x61, count: 10), fin: false),
                    maskedFrame(opcode: .continuation, bytes: Array(repeating: 0x62, count: 10)),
                ]
            )
            #expect(code == 1_009)
        }
    }

    @Test("Invalid UTF8 text closes with invalid-payload status")
    func responsesWebSocketRejectsInvalidUTF8() async throws {
        let fixture = try makeFixture()
        let app = try makeWebSocketApplication(fixture: fixture)
        try await app.test(.ahc()) { client in
            let port = try #require(client.port)
            let code = try await rawWebSocketCloseCode(
                port: port,
                frames: [maskedFrame(opcode: .text, bytes: [0xFF])]
            )
            #expect(code == 1_007)
        }
    }

    @Test("WS and WSS answer ping frames without waiting for their heartbeat", arguments: [false, true])
    func responsesWebSocketPingFrames(useTLS: Bool) async throws {
        let fixture = try makeFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM, authorityPEM: issued.authorityPEM, keyPEM: issued.keyPEM)
        let app = try makeWebSocketApplication(fixture: fixture, tlsIdentity: useTLS ? identity : nil)
        try await app.test(.ahc()) { client in
            let port = try #require(client.port)
            let socket = try await connectRawWebSocket(port: port, authority: useTLS ? identity.authority : nil)
            let timeout = socket.channel.eventLoop.scheduleTask(in: .seconds(5)) {
                socket.channel.close(promise: nil)
            }
            defer { timeout.cancel() }
            try await socket.executeThenClose { inbound, outbound in
                var iterator = inbound.makeAsyncIterator()
                for bytes: [UInt8] in [[], [0x61]] {
                    try await outbound.write(maskedFrame(opcode: .ping, bytes: bytes))
                    let pong = try #require(try await iterator.next())
                    #expect(pong.opcode == .pong)
                    #expect(Array(pong.unmaskedData.readableBytesView) == bytes)
                }
                try await outbound.write(maskedFrame(opcode: .connectionClose, bytes: [0x03, 0xE8]))
                let close = try #require(try await iterator.next())
                #expect(close.opcode == .connectionClose)
            }
        }
    }

    @Test("An idle peer that ignores close cannot extend the connection lifetime", arguments: [false, true])
    func responsesWebSocketDeadlineClosesUnresponsivePeer(useTLS: Bool) async throws {
        let fixture = try makeFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM, authorityPEM: issued.authorityPEM, keyPEM: issued.keyPEM)
        var limits = ResponsesWebSocketLimits()
        limits.connectionLifetimeSeconds = 1
        limits.closeGraceSeconds = 1
        let app = try makeWebSocketApplication(
            fixture: fixture, tlsIdentity: useTLS ? identity : nil, limits: limits)
        try await app.test(.ahc()) { client in
            let port = try #require(client.port)
            let socket = try await connectRawWebSocket(port: port, authority: useTLS ? identity.authority : nil)
            let testTimeout = socket.channel.eventLoop.scheduleTask(in: .seconds(4)) {
                socket.channel.close(promise: nil)
            }
            defer { testTimeout.cancel() }
            try await socket.executeThenClose { inbound, _ in
                var iterator = inbound.makeAsyncIterator()
                let errorFrame = try #require(try await iterator.next())
                #expect(errorFrame.opcode == .text)
                let error = try #require(JSONValue.parse(Data(errorFrame.unmaskedData.readableBytesView)).object)
                #expect(error["error"]?.object?["code"] == .string("websocket_connection_limit_reached"))
                let close = try #require(try await iterator.next())
                #expect(close.opcode == .connectionClose)
                // Deliberately do not reply with a WebSocket close or TLS
                // close-notify. The server must still release the socket.
                try await socket.channel.closeFuture.get()
            }
            testTimeout.cancel()
            do {
                try await testTimeout.futureResult.get()
                Issue.record("The test timeout fired before the server's physical deadline")
            } catch EventLoopError.cancelled {}
        }
    }
}

private func maskedFrame(opcode: WebSocketOpcode, bytes: [UInt8], fin: Bool = true) -> WebSocketFrame {
    WebSocketFrame(fin: fin, opcode: opcode, maskKey: [0x01, 0x02, 0x03, 0x04], data: ByteBuffer(bytes: bytes))
}

private typealias RawWebSocketChannel = NIOAsyncChannel<WebSocketFrame, WebSocketFrame>

/// Foundation cannot emit malformed text or choose fragmentation. The NIO
/// upgrader and codecs let these tests write exact frames without hand-rolling
/// the handshake, framing or masking implementations they exercise.
private func rawWebSocketCloseCode(port: Int, frames: [WebSocketFrame]) async throws -> UInt16 {
    let socket = try await connectRawWebSocket(port: port)
    let timeout = socket.channel.eventLoop.scheduleTask(in: .seconds(5)) {
        socket.channel.close(promise: nil)
    }
    defer { timeout.cancel() }
    return try await socket.executeThenClose { inbound, outbound in
        for frame in frames {
            try await outbound.write(frame)
        }
        var iterator = inbound.makeAsyncIterator()
        let close = try #require(try await iterator.next())
        #expect(close.opcode == .connectionClose)
        let payload = close.unmaskedData
        let code = try #require(payload.getInteger(at: payload.readerIndex, as: UInt16.self))
        do {
            try await outbound.write(
                WebSocketFrame(
                    fin: true, opcode: .connectionClose, maskKey: [0x01, 0x02, 0x03, 0x04], data: payload))
        } catch let error as ChannelError {
            guard !socket.channel.isActive, error == .ioOnClosedChannel || error == .alreadyClosed else { throw error }
            // Protocol errors may close the transport immediately after its
            // validated close frame, before this acknowledgement is written.
        }
        return code
    }
}

private func connectRawWebSocket(port: Int, authority: NIOSSLCertificate? = nil) async throws -> RawWebSocketChannel {
    let sslContext: NIOSSLContext? = try authority.map { authority in
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.trustRoots = .certificates([authority])
        return try NIOSSLContext(configuration: configuration)
    }
    let upgraded = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .connectTimeout(.seconds(5))
        .connect(host: "localhost", port: port) { channel in
            channel.eventLoop.makeCompletedFuture {
                if let sslContext {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: sslContext, serverHostname: "localhost"))
                }
                let upgrader = NIOTypedWebSocketClientUpgrader<RawWebSocketChannel> { channel, _ in
                    channel.eventLoop.makeCompletedFuture {
                        try RawWebSocketChannel(wrappingChannelSynchronously: channel)
                    }
                }
                let configuration = NIOTypedHTTPClientUpgradeConfiguration(
                    upgradeRequestHead: HTTPRequestHead(
                        version: .http1_1,
                        method: .GET,
                        uri: "/v1/responses",
                        headers: ["Host": "localhost:\(port)"]
                    ),
                    upgraders: [upgrader]
                ) { channel in
                    channel.eventLoop.makeFailedFuture(RawWebSocketTestError.upgradeRejected)
                }
                return try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                    configuration: .init(upgradeConfiguration: configuration)
                )
            }
        }
    return try await upgraded.get()
}

private enum RawWebSocketTestError: Error {
    case upgradeRejected
}
