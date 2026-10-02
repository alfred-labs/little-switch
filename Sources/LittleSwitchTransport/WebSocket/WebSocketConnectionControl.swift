import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import NIOWebSocket

enum WebSocketUpgradeOutcome: Sendable {
    case upgraded(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, WebSocketCompressionNegotiation)
    case rejected(EventLoopFuture<UpstreamWebSocketHTTPResponse>)
}

struct WebSocketConnectionControl: Sendable {
    let eventLoop: any EventLoop
    let state: NIOLoopBoundBox<WebSocketConnectionState>
    let handshake: EventLoopFuture<WebSocketUpgradeOutcome>
    let abortSignal: EventLoopFuture<Void>

    init(eventLoop: any EventLoop, configuration: UpstreamWebSocketConfiguration) {
        self.eventLoop = eventLoop
        let promise = eventLoop.makePromise(of: WebSocketUpgradeOutcome.self)
        let signal = eventLoop.makePromise(of: Void.self)
        self.handshake = promise.futureResult
        self.abortSignal = signal.futureResult
        self.state = .makeBoxSendingValue(
            WebSocketConnectionState(
                eventLoop: eventLoop, configuration: configuration, handshake: promise, signal: signal),
            eventLoop: eventLoop)
    }

    func abort(_ error: any Error) {
        eventLoop.execute { state.value.abort(error) }
    }

    func normalized(_ error: any Error) async -> any Error {
        do {
            let failure = try await eventLoop.submit { state.value.normalized(error) }.get()
            return (failure as? WebSocketOperationFailure)?.underlying ?? failure
        } catch {
            return error
        }
    }

    func close() async {
        let closing = eventLoop.flatSubmit {
            state.value.finishScope()
            guard let channel = state.value.channel else { return eventLoop.makeSucceededVoidFuture() }
            channel.close(promise: nil)
            return channel.closeFuture
        }
        try? await closing.get()
    }

    func finishSignal() {
        eventLoop.execute { state.value.finishSignal() }
    }
}

final class WebSocketConnectionState {
    let eventLoop: any EventLoop
    let configuration: UpstreamWebSocketConfiguration
    var channel: (any Channel)?
    var tlsCloseContext: ChannelHandlerContext?
    var writerQueue: WebSocketMessageQueue?
    private(set) var peerClose: UpstreamWebSocketPeerClose?
    var diagnostics = UpstreamWebSocketDiagnostics()
    private let handshake: EventLoopPromise<WebSocketUpgradeOutcome>
    private let signal: EventLoopPromise<Void>
    private var handshakeFinished = false
    private var signalFinished = false
    private var upgraded = false
    private var ended = false
    private var physicallyClosed = false
    private var closeSent = false
    private var closeWriteCompleted = false
    private var closeWriteWaiter: EventLoopPromise<Void>?
    private var localCloseWriteResult: Result<Void, any Error>?
    private var localCloseWriteWaiter: EventLoopPromise<Void>?
    private var dataWrite: (identifier: UUID, promise: EventLoopPromise<Void>)?
    private var readerClaimed = false
    private var failure: (any Error)?
    private var responseHead: HTTPResponseHead?
    private var responseBody = Data()
    private var responseState: UpstreamWebSocketHTTPResponse.BodyState = .notApplicable
    private var rejection: EventLoopPromise<UpstreamWebSocketHTTPResponse>?
    private var rejectionFinished = false
    private var handshakeDeadline: Scheduled<Void>?
    private var rejectionDeadline: Scheduled<Void>?
    private var closeDeadline: Scheduled<Void>?

    init(
        eventLoop: any EventLoop,
        configuration: UpstreamWebSocketConfiguration,
        handshake: EventLoopPromise<WebSocketUpgradeOutcome>,
        signal: EventLoopPromise<Void>
    ) {
        self.eventLoop = eventLoop
        self.configuration = configuration
        self.handshake = handshake
        self.signal = signal
    }

    func armHandshakeDeadline(control: WebSocketConnectionControl) {
        handshakeDeadline = eventLoop.scheduleTask(in: configuration.handshakeTimeout.webSocketTimeAmount) {
            control.state.value.expireHandshake()
        }
    }

    func register(_ channel: any Channel) throws {
        self.channel = channel
        if let failure { throw failure }
    }

    func completeHandshake(_ result: Result<WebSocketUpgradeOutcome, any Error>) {
        guard !handshakeFinished else { return }
        handshakeFinished = true
        switch result {
        case .success(let outcome):
            if case .upgraded = outcome {
                upgraded = true
                cancelDeadlines()
            }
            handshake.succeed(outcome)
        case .failure(let error):
            handshake.fail(normalized(error))
        }
    }

    func observe(_ head: HTTPResponseHead) {
        responseHead = head
    }

    func startRejection(control: WebSocketConnectionControl) -> EventLoopFuture<UpstreamWebSocketHTTPResponse> {
        let promise = eventLoop.makePromise(of: UpstreamWebSocketHTTPResponse.self)
        rejection = promise
        responseState = .connectionClosed
        rejectionDeadline = eventLoop.scheduleTask(in: configuration.rejectionBodyTimeout.webSocketTimeAmount) {
            control.state.value.finishRejection(.deadlineExpired)
        }
        return promise.futureResult
    }

    func appendRejection(_ buffer: ByteBuffer) {
        guard !rejectionFinished else { return }
        let available = configuration.maximumRejectionBodyBytes - responseBody.count
        responseBody.append(contentsOf: buffer.readableBytesView.prefix(available))
        if buffer.readableBytes >= available { finishRejection(.limitReached) }
    }

    func finishRejection(_ bodyState: UpstreamWebSocketHTTPResponse.BodyState) {
        guard let rejection, let responseHead, !rejectionFinished else { return }
        rejectionFinished = true
        responseState = bodyState
        cancelDeadlines()
        rejection.succeed(.init(head: responseHead, bodyPrefix: responseBody, bodyState: bodyState))
        closeSocket()
    }

    func abort(_ error: any Error) {
        guard failure == nil else { return }
        let error = normalized(error)
        failure = error
        cancelDeadlines()
        settleDataWrite(.failure(error))
        settleLocalCloseWrite(.failure(error))
        closeWriteWaiter?.fail(error)
        closeWriteWaiter = nil
        if let rejection, !rejectionFinished {
            rejectionFinished = true
            rejection.fail(error)
        }
        writerQueue?.failAll(
            error as? UpstreamWebSocketFailure
                ?? .init(
                    kind: error is CancellationError ? .cancelled : .connectionLost))
        if !signalFinished {
            signalFinished = true
            signal.fail(error)
        }
        completeHandshake(.failure(error))
        closeSocket()
    }

    func normalized(_ error: any Error) -> any Error {
        if let failure { return failure }
        if error is UpstreamWebSocketFailure || error is CancellationError || error is WebSocketOperationFailure {
            return error
        }
        if upgraded { return UpstreamWebSocketFailure(kind: .connectionLost) }
        if let responseHead {
            let response = UpstreamWebSocketHTTPResponse(
                head: responseHead, bodyPrefix: responseBody, bodyState: responseState)
            return UpstreamWebSocketFailure(
                kind: responseHead.status == .switchingProtocols ? .invalidUpgrade : .upgradeRejected,
                response: response)
        }
        if error is NIOSSLError || error is NIOSSLExtraError || error is BoringSSLError {
            return UpstreamWebSocketFailure(kind: .tlsFailed)
        }
        return UpstreamWebSocketFailure(kind: .connectionFailed)
    }

    func cancelDeadlines() {
        handshakeDeadline?.cancel()
        rejectionDeadline?.cancel()
        closeDeadline?.cancel()
        handshakeDeadline = nil
        rejectionDeadline = nil
        closeDeadline = nil
    }

    func installWriter(control: WebSocketConnectionControl) throws {
        if let failure { throw failure }
        guard !ended else { throw UpstreamWebSocketFailure(kind: .connectionEnded) }
        writerQueue = WebSocketMessageQueue(control: control, configuration: configuration)
        if peerClose != nil || closeSent { writerQueue?.peerClosed() }
    }

    func claimReader() throws {
        guard !ended else { throw UpstreamWebSocketFailure(kind: .connectionEnded) }
        guard !readerClaimed else { throw UpstreamWebSocketFailure(kind: .inboundAlreadyConsumed) }
        if let failure { throw failure }
        readerClaimed = true
    }

    func receivedClose(_ close: UpstreamWebSocketPeerClose, control: WebSocketConnectionControl) {
        guard peerClose == nil else { return }
        peerClose = close
        if diagnostics.closeOrigin == nil { diagnostics.closeOrigin = .peer }
        diagnostics.peerCloseCode = close.code
        armCloseDeadline(control: control)
        writerQueue?.peerClosed()
        settleDataWrite(.success(()))
    }

    var permitsDataFrames: Bool {
        failure == nil && !ended && !physicallyClosed && !closeSent && peerClose == nil
    }

    func beginDataWrite() -> EventLoopFuture<Void>? {
        guard permitsDataFrames else { return nil }
        precondition(dataWrite == nil, "The message pump must join each fragment write")
        let promise = eventLoop.makePromise(of: Void.self)
        dataWrite = (UUID(), promise)
        return promise.futureResult
    }

    var dataWriteIdentifier: UUID? { dataWrite?.identifier }

    func completedDataWrite(_ identifier: UUID?, result: Result<Void, any Error>) {
        // A close or cancellation can release the pump before a lower write settles.
        // Its late completion must not acknowledge a different frame or replace the close.
        guard let identifier, dataWrite?.identifier == identifier else { return }
        switch result {
        case .success: settleDataWrite(.success(()))
        case .failure: abort(UpstreamWebSocketFailure(kind: .writeFailed))
        }
    }

    private func settleDataWrite(_ result: Result<Void, any Error>) {
        let pending = dataWrite
        dataWrite = nil
        pending?.promise.completeWith(result)
    }

    func sentClose(code: UInt16? = nil) {
        if diagnostics.closeOrigin == nil { diagnostics.closeOrigin = .local }
        diagnostics.localCloseCode = code
        closeSent = true
        writerQueue?.closeFrameSent()
        settleDataWrite(.success(()))
    }

    func physicalConnectionClosed() {
        physicallyClosed = true
        closeDeadline?.cancel()
        closeDeadline = nil
        settleLocalCloseWrite(.failure(UpstreamWebSocketFailure(kind: .writeFailed)))
        if peerClose != nil { settledCloseWrite() }
    }

    func completedCloseWrite(_ result: Result<Void, any Error>) {
        let localResult = result.mapError { _ in UpstreamWebSocketFailure(kind: .writeFailed) as any Error }
        settleLocalCloseWrite(localResult)
        if case .failure = result, !(physicallyClosed && peerClose != nil) {
            abort(UpstreamWebSocketFailure(kind: .writeFailed))
            return
        }
        settledCloseWrite()
    }

    func waitForLocalCloseWrite() -> EventLoopFuture<Void> {
        if let localCloseWriteResult { return eventLoop.makeCompletedFuture(localCloseWriteResult) }
        if let localCloseWriteWaiter { return localCloseWriteWaiter.futureResult }
        let promise = eventLoop.makePromise(of: Void.self)
        localCloseWriteWaiter = promise
        return promise.futureResult
    }

    private func settleLocalCloseWrite(_ result: Result<Void, any Error>) {
        guard localCloseWriteResult == nil else { return }
        localCloseWriteResult = result
        localCloseWriteWaiter?.completeWith(result)
        localCloseWriteWaiter = nil
    }

    private func settledCloseWrite() {
        closeWriteCompleted = true
        closeWriteWaiter?.succeed(())
        closeWriteWaiter = nil
    }

    func waitForCloseWrite() -> EventLoopFuture<Void> {
        if let failure { return eventLoop.makeFailedFuture(failure) }
        guard peerClose != nil else {
            return eventLoop.makeFailedFuture(UpstreamWebSocketFailure(kind: .connectionLost))
        }
        if physicallyClosed || closeWriteCompleted { return eventLoop.makeSucceededVoidFuture() }
        if let closeWriteWaiter { return closeWriteWaiter.futureResult }
        let promise = eventLoop.makePromise(of: Void.self)
        closeWriteWaiter = promise
        return promise.futureResult
    }

    func receivedPeerClose() throws -> UpstreamWebSocketPeerClose {
        if let failure { throw failure }
        guard let peerClose else { throw UpstreamWebSocketFailure(kind: .connectionLost) }
        return peerClose
    }

    func armCloseDeadline(control: WebSocketConnectionControl) {
        guard closeDeadline == nil, !physicallyClosed else { return }
        closeDeadline = eventLoop.scheduleTask(in: configuration.closeTimeout.webSocketTimeAmount) {
            control.state.value.abort(UpstreamWebSocketFailure(kind: .closeTimedOut))
        }
    }

    func finishScope() {
        ended = true
        cancelDeadlines()
        settleDataWrite(.failure(UpstreamWebSocketFailure(kind: .connectionEnded)))
        settleLocalCloseWrite(.failure(UpstreamWebSocketFailure(kind: .connectionEnded)))
        writerQueue?.failAll(.init(kind: .connectionEnded))
        writerQueue = nil
        tlsCloseContext = nil
        finishSignal()
    }

    func finishSignal() {
        guard !signalFinished else { return }
        signalFinished = true
        signal.succeed(())
    }

    private func expireHandshake() {
        if rejection != nil {
            finishRejection(.deadlineExpired)
        } else {
            abort(UpstreamWebSocketFailure(kind: .handshakeTimedOut))
        }
    }

    private func closeSocket() {
        // Abort underneath TLS: a peer ignoring close_notify must not extend the
        // configured WS deadline or hold a cancelled connection open.
        if let tlsCloseContext {
            tlsCloseContext.close(promise: nil)
        } else {
            channel?.close(promise: nil)
        }
    }
}

extension Duration {
    var webSocketTimeAmount: TimeAmount {
        let parts = components
        return .nanoseconds(parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000)
    }
}
