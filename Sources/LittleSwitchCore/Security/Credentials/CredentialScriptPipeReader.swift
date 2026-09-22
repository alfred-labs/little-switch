import Foundation
import os

/// Delivers one pipe's bytes through `readabilityHandler`, the only
/// Foundation primitive that a cancelled task can actually stop: plain
/// `readToEnd` and `bytes` iteration both block past cancellation while
/// any inherited write end stays open. The handler retains bounded chunks and
/// finishes on EOF (the empty chunk); cancellation finishes early with
/// the bytes already delivered.
final class CredentialScriptPipeReader: Sendable {
    private struct State {
        var buffer: CredentialScriptOutputBuffer
        var continuation: CheckedContinuation<Data, Never>?
        var finished = false
    }

    private let handle: FileHandle
    private let state: OSAllocatedUnfairLock<State>
    private let onLimitExceeded: @Sendable () -> Void

    init(
        handle: FileHandle,
        retention: CredentialScriptOutputBuffer.Retention = .prefix(65_536),
        onLimitExceeded: @escaping @Sendable () -> Void = {}
    ) {
        self.handle = handle
        state = OSAllocatedUnfairLock(initialState: State(buffer: CredentialScriptOutputBuffer(retention: retention)))
        self.onLimitExceeded = onLimitExceeded
    }

    var exceededLimit: Bool {
        state.withLock { $0.buffer.exceededLimit }
    }

    func read() async -> Data {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let onLimitExceeded = self.onLimitExceeded
                let installed = state.withLock { state -> Bool in
                    if state.finished || state.continuation != nil {
                        return false
                    }
                    state.continuation = continuation
                    // Installation and the terminal flag share one lock, so
                    // cancellation cannot disarm a handler before it is installed.
                    // Capture the state rather than the reader to avoid a cycle.
                    handle.readabilityHandler = { [state = self.state] readable in
                        let chunk = readable.availableData
                        if chunk.isEmpty {
                            Self.finish(readable, state: state)
                        } else {
                            let firstExcess = state.withLock { state in
                                guard !state.finished else { return false }
                                return state.buffer.append(chunk)
                            }
                            if firstExcess {
                                onLimitExceeded()
                            }
                        }
                    }
                    return true
                }
                guard installed else {
                    continuation.resume(returning: Data())
                    return
                }
            }
        } onCancel: {
            finish()
        }
    }

    private func finish() {
        Self.finish(handle, state: state)
    }

    /// Idempotent: any call disarms the handler, and only a still-pending
    /// continuation resumes — cancellation racing EOF can land both calls.
    private static func finish(
        _ handle: FileHandle,
        state: OSAllocatedUnfairLock<State>
    ) {
        let completion = state.withLock { state -> (CheckedContinuation<Data, Never>?, Data) in
            state.finished = true
            let pending = state.continuation
            state.continuation = nil
            return (pending, state.buffer.data)
        }
        handle.readabilityHandler = nil
        completion.0?.resume(returning: completion.1)
    }
}
