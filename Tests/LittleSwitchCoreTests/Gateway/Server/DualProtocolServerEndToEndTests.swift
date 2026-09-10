import AsyncHTTPClient
import Foundation
import HummingbirdCore
import LittleSwitchTransport
import Logging
import NIOCore
import NIOEmbedded
import NIOSSL
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    /// The whole point of the dual-protocol listener: one port, both wire
    /// protocols, one responder. Drives the real GatewayServer — builder,
    /// sniffer, TLS accept, HTTP handling — over a real socket.
    @Test("The shared listener serves plain HTTP and TLS on one port")
    func dualProtocolListenerServesBothProtocols() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )

        let (server, port) = try await Self.startDualProtocolServer(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            tlsIdentity: identity
        )
        defer { Task { await server.stop() } }

        let plainClient = HTTPClient(eventLoopGroupProvider: .singleton)
        defer { Task { try? await plainClient.shutdown() } }
        let plain = try await plainClient.execute(
            HTTPClientRequest(url: "http://127.0.0.1:\(port)/api/about"),
            timeout: .seconds(20)
        )
        #expect(plain.status == .ok)
        let plainBody = try await plain.body.collect(upTo: 1_024 * 1_024)
        #expect(
            String(buffer: plainBody).contains(ProductIdentity.displayName)
        )

        var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
        tlsConfiguration.certificateVerification = .none
        let tlsClient = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(tlsConfiguration: tlsConfiguration)
        )
        defer { Task { try? await tlsClient.shutdown() } }
        let secure = try await tlsClient.execute(
            HTTPClientRequest(url: "https://localhost:\(port)/api/about"),
            timeout: .seconds(20)
        )
        #expect(secure.status == .ok)
        let secureBody = try await secure.body.collect(upTo: 1_024 * 1_024)
        #expect(
            String(buffer: secureBody).contains(ProductIdentity.displayName)
        )
    }

    /// Binds one of a few high ports; collisions with a busy port just move on.
    private static func startDualProtocolServer(
        state: GatewayState,
        transport: any UpstreamTransport,
        secretStore: any SecretStore,
        tlsIdentity: GatewayTLSIdentity
    ) async throws -> (GatewayServer, port: Int) {
        var lastError: (any Swift.Error)?
        for attempt in 0..<5 {
            let port = 21_436 + attempt * 7 + Int.random(in: 0...3)
            let server = GatewayServer(
                state: state,
                transport: transport,
                secretStore: secretStore,
                listenPort: port,
                requiredAuthorityPort: nil,
                tlsIdentity: tlsIdentity
            )
            do {
                try await server.start()
                return (server, port)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GatewayServer.Error.stoppedBeforeReady
    }
}

@Suite("Dual-protocol channel machinery")
struct DualProtocolChannelMachineryTests {
    private func makeHTTPChannel() -> HTTP1Channel {
        HTTP1Channel(
            responder: { _, _, _ in
                throw CancellationError()
            }, configuration: .init())
    }

    private func makeChannelAndState() throws -> (
        channel: EmbeddedChannel,
        state: DualProtocolChannelState
    ) {
        let channel = EmbeddedChannel()
        let http = makeHTTPChannel()
        let state = DualProtocolChannelState()
        let sniffer = ProtocolSniffHandler(
            plainSetup: { channel, logger in
                http.setup(channel: channel, logger: logger)
            },
            secureSetup: { channel, logger in
                http.setup(channel: channel, logger: logger)
            },
            completion: state.complete,
            logger: Logger(label: "test")
        )
        try channel.pipeline.syncOperations.addHandler(sniffer)
        return (channel, state)
    }

    @Test("Completion before waiting hands the stored value over")
    func completeBeforeWait() async throws {
        let (channel, state) = try makeChannelAndState()
        // A plain HTTP byte drives the sniffer into the plain setup, which
        // completes the state before anyone waits on it.
        channel.pipeline.fireChannelRead(ByteBuffer(string: "G"))
        let value = try? await state.waitForValue()
        #expect(value != nil)
        _ = try? channel.finish()
    }

    @Test("A failing setup completes the state with the failure")
    func failingSetup() async throws {
        struct Injected: Error {}
        let channel = EmbeddedChannel()
        let state = DualProtocolChannelState()
        let sniffer = ProtocolSniffHandler(
            plainSetup: { channel, _ in
                channel.eventLoop.makeFailedFuture(Injected())
            },
            secureSetup: { channel, _ in
                channel.eventLoop.makeFailedFuture(Injected())
            },
            completion: state.complete,
            logger: Logger(label: "test")
        )
        try channel.pipeline.syncOperations.addHandler(sniffer)
        channel.pipeline.fireChannelRead(ByteBuffer(string: "G"))
        do {
            _ = try await state.waitForValue()
            Issue.record("expected a failure")
        } catch {}
        _ = try? channel.finish()
    }

    @Test("handle() returns early when the state failed")
    func handleReturnsEarlyOnFailure() async throws {
        struct Injected: Error {}
        let channel = EmbeddedChannel()
        let state = DualProtocolChannelState()
        state.complete(.failure(Injected()))
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let dual = DualProtocolChannel(
            http: makeHTTPChannel(),
            sslContext: try NIOSSLContext(configuration: identity.tlsConfiguration)
        )
        await dual.handle(
            value: DualProtocolChannelValue(channel: channel, state: state),
            logger: Logger(label: "test")
        )
        _ = try? channel.finish()
    }

    @Test("A connection that never speaks is closed, not held")
    func silentConnectionTimesOut() async throws {
        let (channel, state) = try makeChannelAndState()
        // No byte, and no close either. Without a deadline this channel and
        // its suspended `handle` task are held for as long as the peer
        // cares to keep the socket open — one idle socket each, for free.
        channel.embeddedEventLoop.advanceTime(by: ProtocolSniffLimits.decisionTimeout)
        do {
            _ = try await state.waitForValue()
            Issue.record("expected a failure")
        } catch let error as ProtocolSniffHandler<HTTP1Channel.Value>.SniffError {
            #expect(error == .firstByteTimedOut)
        }
        _ = try? channel.finish()
    }

    @Test("A first read too large to be a handshake is refused")
    func oversizedPendingBytesAreRefused() async throws {
        let (channel, state) = try makeChannelAndState()
        // NIO's own read ceiling is 64 KiB, so a single read past it is not
        // a client waiting for the decision — and everything buffered here
        // is held with no upper bound until the chosen pipeline is in.
        let oversized = ProtocolSniffLimits.maximumPendingBytes + 1
        channel.pipeline.fireChannelRead(
            ByteBuffer(repeating: 0x47, count: oversized)
        )
        do {
            _ = try await state.waitForValue()
            Issue.record("expected a failure")
        } catch let error as ProtocolSniffHandler<HTTP1Channel.Value>.SniffError {
            #expect(error == .tooManyBytesBeforeSetup)
        }
        _ = try? channel.finish()
    }

    @Test("A pipeline error completes the state with the failure")
    func errorCaughtCompletes() async throws {
        struct Injected: Error {}
        let (channel, state) = try makeChannelAndState()
        channel.pipeline.fireErrorCaught(Injected())
        do {
            _ = try await state.waitForValue()
            Issue.record("expected a failure")
        } catch {}
        _ = try? channel.finish()
    }
}

extension DualProtocolChannelMachineryTests {
    @Test("A peer that leaves without a byte resolves the waiter")
    func silentConnectionFailsFast() async throws {
        let (channel, state) = try makeChannelAndState()
        channel.pipeline.fireChannelInactive()
        do {
            _ = try await state.waitForValue()
            Issue.record("expected a failure")
        } catch {}
        _ = try? channel.finish()
    }

    @Test("Bytes arriving before the replay keep their order")
    func bytesAccumulateUntilReplay() throws {
        final class Recorder: ChannelInboundHandler, RemovableChannelHandler {
            typealias InboundIn = ByteBuffer
            var received: [String] = []
            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                var buffer = unwrapInboundIn(data)
                received.append(buffer.readString(length: buffer.readableBytes) ?? "")
            }
        }
        let channel = EmbeddedChannel()
        let recorder = Recorder()
        let state = DualProtocolChannelState()
        let gate = channel.eventLoop.makePromise(of: Void.self)
        let sniffer = ProtocolSniffHandler<HTTP1Channel.Value>(
            plainSetup: { channel, logger in
                gate.futureResult.flatMap {
                    HTTP1Channel { _, _, _ in throw CancellationError() }
                        .setup(channel: channel, logger: logger)
                }
            },
            secureSetup: { channel, logger in
                gate.futureResult.flatMap {
                    HTTP1Channel { _, _, _ in throw CancellationError() }
                        .setup(channel: channel, logger: logger)
                }
            },
            completion: state.complete,
            logger: Logger(label: "test")
        )
        try channel.pipeline.syncOperations.addHandlers([sniffer, recorder])
        // The deciding byte, then more traffic while the setup is still
        // pending: nothing may overtake the buffered replay.
        channel.pipeline.fireChannelRead(ByteBuffer(string: "G"))
        channel.pipeline.fireChannelRead(ByteBuffer(string: "ET / HTTP"))
        #expect(recorder.received.isEmpty)
        gate.succeed(())
        channel.embeddedEventLoop.run()
        #expect(recorder.received == ["GET / HTTP"])
        channel.pipeline.fireChannelRead(ByteBuffer(string: " done"))
        #expect(recorder.received == ["GET / HTTP", " done"])
        _ = try? channel.finish()
    }
}
