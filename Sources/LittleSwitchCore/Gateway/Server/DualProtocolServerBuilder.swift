import Foundation
import HummingbirdCore
import Logging
import NIOCore
import NIOSSL

/// One listener, two wire protocols. The first inbound byte decides: `0x16`
/// is a TLS ClientHello, anything else is plain HTTP — so the Desktop talks
/// https to the gateway on the very port Codex, OpenCode, and terminal
/// Claude Code keep talking plain http to, with no client-side migration
/// forced on anyone.
///
/// Hummingbird runs `setup` as the NIO child-channel initializer, and NIO
/// withholds activation until that initializer completes — so setup must
/// never wait for inbound bytes. It installs only the sniffer and returns a
/// lazy value immediately; the sniffer installs the chosen pipeline once a
/// byte arrives, and `handle` awaits the real HTTP value.
package enum DualProtocolServerBuilder {
    package static func make(
        tlsConfiguration: TLSConfiguration
    ) throws -> HTTPServerBuilder {
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
        return .init { responder in
            // HTTP1Channel(responder:configuration: .init()) is exactly what
            // .http1() builds; the direct construction exists only because
            // HTTPServerBuilder.buildChildChannel is package-scoped.
            DualProtocolChannel(
                http: HTTP1Channel(responder: responder, configuration: .init()),
                sslContext: sslContext
            )
        }
    }
}

/// Bridges the lazy setup: the value appears once the sniffer has chosen
/// the wire protocol, and everyone else waits on it.
final class DualProtocolChannelState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<HTTP1Channel.Value, any Error>, Never>?
    private var result: Result<HTTP1Channel.Value, any Error>?
    private var settled = false

    /// First caller wins: channel events can race (a close behind a decided
    /// setup, an error behind a success), and `handle` must never observe a
    /// failure that a byte already superseded.
    func complete(_ result: Result<HTTP1Channel.Value, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else {
            return
        }
        settled = true
        if let continuation {
            continuation.resume(returning: result)
            self.continuation = nil
        } else {
            self.result = result
        }
    }

    func waitForValue() async throws -> HTTP1Channel.Value {
        let outcome: Result<HTTP1Channel.Value, any Error> =
            await withCheckedContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }
                if let stored = result {
                    continuation.resume(returning: stored)
                } else {
                    self.continuation = continuation
                }
            }
        return try outcome.get()
    }
}

struct DualProtocolChannelValue: ServerChildChannelValue {
    let channel: any Channel
    let state: DualProtocolChannelState
}

struct DualProtocolChannel: ServerChildChannel {
    typealias Value = DualProtocolChannelValue

    let http: HTTP1Channel
    let sslContext: NIOSSLContext

    func setup(channel: any Channel, logger: Logger) -> EventLoopFuture<Value> {
        let state = DualProtocolChannelState()
        let sniffer = ProtocolSniffHandler(
            plainSetup: { channel, logger in
                http.setup(channel: channel, logger: logger)
            },
            secureSetup: { channel, logger in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLServerHandler(context: sslContext)
                    )
                }
                .flatMap {
                    http.setup(channel: channel, logger: logger)
                }
            },
            completion: state.complete,
            logger: logger
        )
        return channel.pipeline.addHandler(sniffer).map {
            DualProtocolChannelValue(channel: channel, state: state)
        }
    }

    func handle(value: Value, logger: Logger) async {
        guard let httpValue = try? await value.state.waitForValue() else {
            return
        }
        await http.handle(value: httpValue, logger: logger)
    }
}

/// What bounds a connection that has not yet said which protocol it speaks.
///
/// These belong to the sniffer and are kept beside it rather than on it:
/// `ProtocolSniffHandler` is generic over the setup's value, and Swift has
/// no storage for a `static let` in a generic type. Computing them per
/// access would work and would say the wrong thing — they are two fixed
/// numbers, not a policy that varies with the pipeline being built.
enum ProtocolSniffLimits {
    /// How long a connection may hold the listener without saying which
    /// protocol it speaks.
    ///
    /// A peer that opens a socket and then says nothing never reaches
    /// `channelInactive`, so with no deadline it holds a channel and a
    /// suspended `handle` task for as long as it likes — one idle socket
    /// each, for free. That is tolerable on the loopback and is not
    /// tolerable once the gateway is reachable from the network, which is
    /// a supported configuration.
    static let decisionTimeout = TimeAmount.seconds(10)

    /// The most that may pile up before the chosen pipeline is installed.
    ///
    /// The decision needs one byte; everything after it accumulates only
    /// because the setup future has not resolved yet, and that window is
    /// short. A peer that fills it is not waiting for a handshake.
    static let maximumPendingBytes = 64 * 1_024
}

/// Holds inbound bytes until one is readable, then installs the plain or
/// TLS pipeline and replays what it held back. After the decision the
/// sniffer stays in the pipeline as a pass-through: bytes keep flowing to
/// whichever handlers the chosen setup appended behind it.
///
/// Mutated only on the channel's event loop; NIO delivers every callback
/// there, so the unchecked conformance is confinement, not a race.
final class ProtocolSniffHandler<Value>: ChannelInboundHandler,
    RemovableChannelHandler, @unchecked Sendable
where Value: Sendable {
    typealias InboundIn = ByteBuffer

    typealias Setup =
        @Sendable (
            _ channel: any Channel,
            _ logger: Logger
        ) -> EventLoopFuture<Value>

    private enum Decision {
        case pending
        case plain
        case secure
    }

    enum SniffError: Error, Equatable {
        case closedBeforeFirstByte
        case firstByteTimedOut
        case tooManyBytesBeforeSetup
    }

    private let plainSetup: Setup
    private let secureSetup: Setup
    private let completion: @Sendable (Result<Value, any Error>) -> Void
    private let logger: Logging.Logger
    private var buffered: ByteBuffer?
    private var decision: Decision = .pending
    /// Bytes keep accumulating until the buffered ones have been replayed:
    /// the setups may complete asynchronously, and anything forwarded
    /// before the replay would overtake it and corrupt the stream.
    private var replayed = false
    private var deadline: Scheduled<Void>?

    init(
        plainSetup: @escaping Setup,
        secureSetup: @escaping Setup,
        completion: @escaping @Sendable (Result<Value, any Error>) -> Void,
        logger: Logging.Logger
    ) {
        self.plainSetup = plainSetup
        self.secureSetup = secureSetup
        self.completion = completion
        self.logger = logger
    }

    /// Arms the deadline as soon as the handler joins the pipeline, which
    /// is before the channel is active: the window being bounded starts at
    /// the connection, not at the first byte that may never come.
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        deadline = context.eventLoop.scheduleTask(in: ProtocolSniffLimits.decisionTimeout) { [self] in
            // Cancellation and firing race on a real loop, so the state is
            // rechecked here rather than trusted from the cancel site.
            guard decision == .pending else { return }
            completion(.failure(SniffError.firstByteTimedOut))
            channel.close(promise: nil)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        cancelDeadline()
    }

    private func cancelDeadline() {
        deadline?.cancel()
        deadline = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if replayed {
            context.fireChannelRead(data)
            return
        }
        var buffer = unwrapInboundIn(data)
        var accumulated = buffered ?? ByteBuffer()
        accumulated.writeBuffer(&buffer)
        guard accumulated.readableBytes <= ProtocolSniffLimits.maximumPendingBytes else {
            completion(.failure(SniffError.tooManyBytesBeforeSetup))
            context.close(promise: nil)
            return
        }
        buffered = accumulated
        guard decision == .pending,
            let buffered, buffered.readableBytes > 0,
            let first = buffered.getBytes(at: buffered.readerIndex, length: 1)?.first
        else {
            return
        }
        decision = first == 0x16 ? .secure : .plain
        cancelDeadline()
        let setup = decision == .secure ? secureSetup : plainSetup
        let channel = context.channel
        setup(channel, logger).whenComplete { result in
            switch result {
            case .success(let value):
                self.completion(.success(value))
                // Retire the sniffing state before replaying: the replay
                // re-enters this handler through the pipeline head, and it
                // must pass through, not be swallowed as fresh input.
                let replay = self.buffered
                self.buffered = nil
                self.replayed = true
                if let replay, replay.readableBytes > 0 {
                    channel.pipeline.fireChannelRead(replay)
                    // The completion event fired while the HTTP handlers
                    // were not installed yet; replay it or the decoder never
                    // finishes its part.
                    channel.pipeline.fireChannelReadComplete()
                }
            case .failure(let error):
                self.completion(.failure(error))
                // Nothing downstream was installed, so nothing downstream
                // will close this: `handle` has already been resolved with
                // the failure and the socket would sit open with no reader.
                channel.close(promise: nil)
            }
        }
    }

    /// A peer that connects and leaves without a byte — every TCP probe,
    /// every aborted client — must resolve `handle`, not park it forever.
    func channelInactive(context: ChannelHandlerContext) {
        cancelDeadline()
        if decision == .pending {
            completion(.failure(SniffError.closedBeforeFirstByte))
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        completion(.failure(error))
        context.fireErrorCaught(error)
        // Same reasoning as a failed setup: before the replay this handler
        // is the only reader the channel has.
        if !replayed {
            context.close(promise: nil)
        }
    }
}
