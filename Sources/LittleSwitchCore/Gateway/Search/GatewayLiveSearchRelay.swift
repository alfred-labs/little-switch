import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

package enum LiveSearchRecovery: Sendable {
    /// Rethrow the original error (cancellation, client write failure).
    case rethrow
    /// Commit the stream as failed without emitting frames or a reason.
    case swallow
    /// Emit failure frames, then commit with the given reason.
    case fail(LiveSearchFail)
}

package struct LiveSearchFail: Sendable {
    let frames: [Data]
    let reason: String?

    package init(frames: [Data], reason: String?) {
        self.frames = frames
        self.reason = reason
    }
}

extension GatewayResponder {
    /// Shared ResponseBody scaffold for the live web-search relays: session
    /// construction, the failure ladder, frame draining, and the committed
    /// failure contract. Protocols supply their session, run loop, frame
    /// writer, and error classification.
    package func liveSearchResponse<Session>(
        makeSession: @autoclosure @escaping @Sendable () -> Session,
        run: @escaping @Sendable (inout Session, inout any ResponseBodyWriter) async throws -> Void,
        writeFrames: @escaping @Sendable (inout any ResponseBodyWriter, [Data]) async throws -> Void,
        recover: @escaping @Sendable (inout Session, any Error) throws -> LiveSearchRecovery
    ) -> Response {
        var headers: HTTPFields = [.contentType: "text/event-stream"]
        if let cacheControl = HTTPField.Name("cache-control") {
            headers[cacheControl] = "no-cache"
        }
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(contentLength: nil) { writer in
                var session = makeSession()
                var committedFailure = false
                var failureReason: String?
                do {
                    try await run(&session, &writer)
                } catch {
                    switch try recover(&session, error) {
                    case .rethrow:
                        throw error
                    case .swallow:
                        committedFailure = true
                    case .fail(let fail):
                        try await writeFrames(&writer, fail.frames)
                        committedFailure = true
                        failureReason = fail.reason
                    }
                }
                try await writer.finish(nil)
                if committedFailure {
                    throw GatewayCommittedStreamFailure(reason: failureReason)
                }
            }
        )
    }

    /// Frame-draining core shared by the per-protocol writers; only the
    /// client-write failure type differs.
    package func writeLiveFrames(
        _ frames: [Data],
        to writer: inout any ResponseBodyWriter,
        clientWriteFailure: (any Error) -> any Error
    ) async throws {
        for frame in frames {
            do {
                try Task.checkCancellation()
                try await writer.write(ByteBuffer(bytes: frame))
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw clientWriteFailure(error)
            }
        }
    }
}
