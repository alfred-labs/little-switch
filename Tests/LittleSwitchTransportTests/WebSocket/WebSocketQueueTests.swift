import Foundation
import NIOCore
import NIOPosix
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketQueueTests {
    @Test func countsActiveMessagesAgainstCapacityAndPreservesSubmissionState() async throws {
        let control = Self.control(maximumMessages: 1, maximumBytes: 4)
        let pending = control.eventLoop.submit {
            try control.state.value.installWriter(control: control)
            let queue = try #require(control.state.value.writerQueue)
            let first = WebSocketWriteTicket(command: .message(.text("1234")), eventLoop: control.eventLoop)
            let overflow = WebSocketWriteTicket(command: .message(.text("x")), eventLoop: control.eventLoop)
            queue.enqueue(first)
            _ = queue.take()
            queue.enqueue(overflow)
            control.state.value.abort(UpstreamWebSocketFailure(kind: .connectionLost))
            return (first.promise.futureResult, overflow.promise.futureResult)
        }
        let results = try await pending.get()
        await Self.expectFailure(results.0, kind: .connectionLost, submission: .mayHaveBeenSubmitted)
        await Self.expectFailure(results.1, kind: .outboundQueueFull, submission: .notSubmitted)
        await control.close()
    }

    @Test func queuedCancellationReleasesBytesAndLeavesOtherMessagesWritable() async throws {
        let control = Self.control(maximumMessages: 3, maximumBytes: 8)
        let pending = control.eventLoop.submit {
            try control.state.value.installWriter(control: control)
            let queue = try #require(control.state.value.writerQueue)
            let first = WebSocketWriteTicket(command: .message(.text("1234")), eventLoop: control.eventLoop)
            let cancelled = WebSocketWriteTicket(command: .message(.text("5678")), eventLoop: control.eventLoop)
            let replacement = WebSocketWriteTicket(command: .message(.text("abcd")), eventLoop: control.eventLoop)
            queue.enqueue(first)
            _ = queue.take()
            queue.enqueue(cancelled)
            queue.cancel(cancelled)
            queue.enqueue(replacement)
            queue.complete(first.identifier)
            _ = queue.take()
            queue.complete(replacement.identifier)
            control.state.value.abort(UpstreamWebSocketFailure(kind: .connectionEnded))
            return (first.promise.futureResult, cancelled.promise.futureResult, replacement.promise.futureResult)
        }
        let results = try await pending.get()
        try await results.0.get()
        await Self.expectFailure(results.1, kind: .cancelled, submission: .notSubmitted)
        try await results.2.get()
        await control.close()
    }

    @Test func activeCancellationAbortsQueuedMessagesWithoutCallingThemSubmitted() async throws {
        let control = Self.control(maximumMessages: 2, maximumBytes: 8)
        let pending = control.eventLoop.submit {
            try control.state.value.installWriter(control: control)
            let queue = try #require(control.state.value.writerQueue)
            let active = WebSocketWriteTicket(command: .message(.text("1234")), eventLoop: control.eventLoop)
            let queued = WebSocketWriteTicket(command: .message(.text("5678")), eventLoop: control.eventLoop)
            queue.enqueue(active)
            _ = queue.take()
            queue.enqueue(queued)
            queue.cancel(active)
            return (active.promise.futureResult, queued.promise.futureResult, queue.take())
        }
        let results = try await pending.get()
        await Self.expectFailure(results.0, kind: .cancelled, submission: .mayHaveBeenSubmitted)
        await Self.expectFailure(results.1, kind: .cancelled, submission: .notSubmitted)
        #expect(try await results.2.get() == nil)
        await control.close()
    }

    @Test func closeIsOrderedAfterAcceptedMessagesAndRejectsLaterSends() async throws {
        let control = Self.control(maximumMessages: 1, maximumBytes: 4)
        let pending = control.eventLoop.submit {
            try control.state.value.installWriter(control: control)
            let queue = try #require(control.state.value.writerQueue)
            let first = WebSocketWriteTicket(command: .message(.text("1234")), eventLoop: control.eventLoop)
            let close = WebSocketWriteTicket(command: .close(1_000, "done"), eventLoop: control.eventLoop)
            let late = WebSocketWriteTicket(command: .message(.text("late")), eventLoop: control.eventLoop)
            queue.enqueue(first)
            let firstTaken = queue.take()
            queue.enqueue(close)
            queue.enqueue(late)
            queue.complete(first.identifier)
            let secondTaken = queue.take()
            queue.complete(close.identifier)
            control.state.value.abort(UpstreamWebSocketFailure(kind: .connectionEnded))
            return (
                firstTaken, secondTaken, first.promise.futureResult, close.promise.futureResult,
                late.promise.futureResult
            )
        }
        let results = try await pending.get()
        let first = try #require(try await results.0.get())
        let second = try #require(try await results.1.get())
        guard case .message(.text("1234")) = first.command, case .close(1_000, "done") = second.command else {
            Issue.record("The close command was not ordered after the accepted data message")
            await control.close()
            return
        }
        try await results.2.get()
        try await results.3.get()
        await Self.expectFailure(results.4, kind: .connectionClosing, submission: .notSubmitted)
        await control.close()
    }

    @Test(arguments: [true, false])
    func closeTransitionFailsActiveAndQueuedTicketsWithTheirSubmissionState(peerInitiated: Bool) async throws {
        let control = Self.control(maximumMessages: 2, maximumBytes: 8)
        let pending = control.eventLoop.submit {
            try control.state.value.installWriter(control: control)
            let queue = try #require(control.state.value.writerQueue)
            let active = WebSocketWriteTicket(command: .message(.text("1234")), eventLoop: control.eventLoop)
            let queued = WebSocketWriteTicket(command: .message(.text("5678")), eventLoop: control.eventLoop)
            queue.enqueue(active)
            _ = queue.take()
            queue.enqueue(queued)
            if peerInitiated {
                control.state.value.receivedClose(.init(code: 1_000), control: control)
            } else {
                control.state.value.sentClose()
            }
            #expect(active.status == .finished)
            #expect(queued.status == .finished)
            if active.status != .finished || queued.status != .finished {
                control.state.value.abort(UpstreamWebSocketFailure(kind: .connectionLost))
            }
            return (active.promise.futureResult, queued.promise.futureResult, queue.take())
        }
        let results = try await pending.get()
        await Self.expectFailure(results.0, kind: .connectionClosing, submission: .mayHaveBeenSubmitted)
        await Self.expectFailure(results.1, kind: .connectionClosing, submission: .notSubmitted)
        #expect(try await results.2.get() == nil)
        control.abort(UpstreamWebSocketFailure(kind: .connectionEnded))
        await control.close()
    }

    @Test(arguments: [true, false])
    func aCloseBeforeWriterInstallationCannotAdmitAMessage(peerInitiated: Bool) async throws {
        let control = Self.control(maximumMessages: 1, maximumBytes: 4)
        let pending = control.eventLoop.submit {
            if peerInitiated {
                control.state.value.receivedClose(.init(code: 1_000), control: control)
            } else {
                control.state.value.sentClose()
            }
            try control.state.value.installWriter(control: control)
            let queue = try #require(control.state.value.writerQueue)
            let late = WebSocketWriteTicket(command: .message(.text("late")), eventLoop: control.eventLoop)
            queue.enqueue(late)
            let next = queue.take()
            control.state.value.abort(UpstreamWebSocketFailure(kind: .connectionLost))
            return (late.promise.futureResult, next)
        }
        let results = try await pending.get()
        await Self.expectFailure(results.0, kind: .connectionEnded, submission: .notSubmitted)
        #expect(try await results.1.get() == nil)
        await control.close()
    }

    private static func control(maximumMessages: Int, maximumBytes: Int) -> WebSocketConnectionControl {
        .init(
            eventLoop: MultiThreadedEventLoopGroup.singleton.next(),
            configuration: .init(
                maximumQueuedMessages: maximumMessages, maximumQueuedBytes: maximumBytes))
    }

    private static func expectFailure(
        _ future: EventLoopFuture<Void>,
        kind: UpstreamWebSocketFailure.Kind,
        submission: UpstreamWebSocketSendFailure.Submission
    ) async {
        await #expect {
            try await future.get()
        } throws: { error in
            guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
            return failure.cause.kind == kind && failure.submission == submission
        }
    }
}
