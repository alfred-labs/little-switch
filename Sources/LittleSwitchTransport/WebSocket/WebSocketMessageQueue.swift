import Foundation
import NIOCore

enum WebSocketWriteCommand: Sendable {
    case message(UpstreamWebSocketMessage)
    case close(UInt16, String?)

    var byteCount: Int {
        switch self {
        case .message(.text(let value)): value.utf8.count
        case .message(.binary(let value)): value.count
        case .close: 0
        }
    }
}

struct WebSocketPendingWrite: Sendable {
    let identifier: UUID
    let command: WebSocketWriteCommand
}

final class WebSocketWriteTicket {
    enum Status { case created, queued, writing, finished }
    let identifier = UUID()
    let command: WebSocketWriteCommand
    let promise: EventLoopPromise<Void>
    var status = Status.created

    init(command: WebSocketWriteCommand, eventLoop: any EventLoop) {
        self.command = command
        self.promise = eventLoop.makePromise()
    }

    func fail(_ cause: UpstreamWebSocketFailure) {
        guard status != .finished else { return }
        let submission: UpstreamWebSocketSendFailure.Submission =
            status == .writing ? .mayHaveBeenSubmitted : .notSubmitted
        status = .finished
        promise.fail(UpstreamWebSocketSendFailure(submission: submission, cause: cause))
    }

    func succeed() {
        guard status != .finished else { return }
        status = .finished
        promise.succeed(())
    }
}

final class WebSocketMessageQueue {
    private let control: WebSocketConnectionControl
    private let configuration: UpstreamWebSocketConfiguration
    private var pending: [WebSocketWriteTicket] = []
    private var active: WebSocketWriteTicket?
    private var waiting: EventLoopPromise<WebSocketPendingWrite?>?
    private var bytes = 0
    private var count = 0
    private var closing = false
    private var closeWritten = false
    private var stopped = false

    init(control: WebSocketConnectionControl, configuration: UpstreamWebSocketConfiguration) {
        self.control = control
        self.configuration = configuration
    }

    func enqueue(_ ticket: WebSocketWriteTicket) {
        guard ticket.status == .created else { return }
        guard !stopped else {
            ticket.fail(.init(kind: .connectionEnded))
            return
        }
        guard !closing else {
            ticket.fail(.init(kind: .connectionClosing))
            return
        }
        switch ticket.command {
        case .message:
            guard ticket.command.byteCount <= configuration.maximumOutboundMessageBytes else {
                ticket.fail(.init(kind: .messageTooLarge))
                return
            }
            guard count < configuration.maximumQueuedMessages,
                ticket.command.byteCount <= configuration.maximumQueuedBytes - bytes
            else {
                ticket.fail(.init(kind: .outboundQueueFull))
                return
            }
            bytes += ticket.command.byteCount
            count += 1
        // swiftlint:disable:next pattern_matching_keywords
        case .close(let code, let reason):
            guard WebSocketCloseValidation.valid(code: code), (reason?.utf8.count ?? 0) <= 123 else {
                ticket.fail(.init(kind: .invalidRequest))
                return
            }
            closing = true
            control.state.value.armCloseDeadline(control: control)
        }
        ticket.status = .queued
        pending.append(ticket)
        offer()
    }

    func take() -> EventLoopFuture<WebSocketPendingWrite?> {
        if stopped || closeWritten { return control.eventLoop.makeSucceededFuture(nil) }
        let promise = control.eventLoop.makePromise(of: WebSocketPendingWrite?.self)
        waiting = promise
        offer()
        return promise.futureResult
    }

    func complete(_ identifier: UUID) {
        guard let ticket = active, ticket.identifier == identifier else { return }
        active = nil
        switch ticket.command {
        case .message:
            bytes -= ticket.command.byteCount
            count -= 1
        case .close:
            closeWritten = true
        }
        ticket.succeed()
    }

    func cancel(_ ticket: WebSocketWriteTicket) {
        guard ticket.status != .finished else { return }
        if ticket.status == .writing {
            control.state.value.abort(UpstreamWebSocketFailure(kind: .cancelled))
            return
        }
        if case .close = ticket.command, ticket.status == .queued {
            control.state.value.abort(UpstreamWebSocketFailure(kind: .cancelled))
            return
        }
        if ticket.status == .queued {
            pending.removeAll { $0.identifier == ticket.identifier }
            bytes -= ticket.command.byteCount
            count -= 1
        }
        ticket.fail(.init(kind: .cancelled))
    }

    func finishOperation() -> EventLoopFuture<Void> {
        if closing || stopped { return control.eventLoop.makeSucceededVoidFuture() }
        let ticket = WebSocketWriteTicket(command: .close(1_000, nil), eventLoop: control.eventLoop)
        enqueue(ticket)
        return ticket.promise.futureResult
    }

    func failAll(_ failure: UpstreamWebSocketFailure) {
        stopped = true
        active?.fail(failure)
        active = nil
        for ticket in pending { ticket.fail(failure) }
        pending.removeAll()
        bytes = 0
        count = 0
        waiting?.succeed(nil)
        waiting = nil
    }

    func peerClosed() {
        if let active, case .close = active.command {
            // A peer reply does not prove that our local close write completed.
            // No messages can follow an active close; let its write resolve it.
            stopped = true
            waiting?.succeed(nil)
            waiting = nil
            return
        }
        failAll(.init(kind: .connectionClosing))
    }

    func closeFrameSent() {
        // A close emitted by WSCore (for example an auto-ping timeout) can run
        // outside the application pump. Its data tickets must fail as well.
        if let active, case .close = active.command { return }
        failAll(.init(kind: .connectionClosing))
    }

    private func offer() {
        guard let waiting, active == nil, !pending.isEmpty else { return }
        self.waiting = nil
        let ticket = pending.removeFirst()
        ticket.status = .writing
        active = ticket
        waiting.succeed(.init(identifier: ticket.identifier, command: ticket.command))
    }
}

struct WebSocketMessageWriter: UpstreamWebSocketOutbound {
    let control: WebSocketConnectionControl

    func send(_ message: UpstreamWebSocketMessage) async throws {
        try await submit(.message(message))
    }

    func close(code: UInt16, reason: String?) async throws {
        try await submit(.close(code, reason))
    }

    func finishOperation() async throws {
        let finishing = control.eventLoop.flatSubmit { () -> EventLoopFuture<Void> in
            guard let queue = control.state.value.writerQueue else {
                return control.eventLoop.makeFailedFuture(UpstreamWebSocketFailure(kind: .connectionEnded))
            }
            return queue.finishOperation()
        }
        try await finishing.get()
    }

    func run(_ write: @escaping @Sendable (WebSocketWriteCommand) async throws -> Void) async throws {
        while true {
            let next = control.eventLoop.flatSubmit {
                control.state.value.writerQueue?.take() ?? control.eventLoop.makeSucceededFuture(nil)
            }
            guard let item = try await next.get() else { return }
            do {
                try await write(item.command)
                try await control.eventLoop.submit { control.state.value.writerQueue?.complete(item.identifier) }.get()
            } catch {
                control.abort(error)
                throw error
            }
        }
    }

    private func submit(_ command: WebSocketWriteCommand) async throws {
        let ticket = NIOLoopBoundBox.makeBoxSendingValue(
            WebSocketWriteTicket(command: command, eventLoop: control.eventLoop),
            eventLoop: control.eventLoop)
        try await withTaskCancellationHandler {
            let submitting = control.eventLoop.flatSubmit {
                if let queue = control.state.value.writerQueue {
                    queue.enqueue(ticket.value)
                } else {
                    ticket.value.fail(.init(kind: .connectionEnded))
                }
                return ticket.value.promise.futureResult
            }
            try await submitting.get()
        } onCancel: {
            control.eventLoop.execute {
                if let queue = control.state.value.writerQueue {
                    queue.cancel(ticket.value)
                } else {
                    ticket.value.fail(.init(kind: .cancelled))
                }
            }
        }
    }
}
