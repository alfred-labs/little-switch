import Foundation
import os

/// Delivers one pipe's bytes through `readabilityHandler`, the only
/// Foundation primitive that a cancelled task can actually stop: plain
/// `readToEnd` and `bytes` iteration both block past cancellation while
/// any inherited write end stays open. The handler appends chunks and
/// finishes on EOF (the empty chunk); cancellation finishes early with
/// the bytes already delivered.
final class CredentialScriptPipeReader: Sendable {
    private struct State {
        var data = Data()
        var continuation: CheckedContinuation<Data, Never>?
    }

    private let handle: FileHandle
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(handle: FileHandle) {
        self.handle = handle
    }

    func read() async -> Data {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let installed = state.withLock { state -> Bool in
                    if state.continuation != nil {
                        return false
                    }
                    state.continuation = continuation
                    return true
                }
                guard installed else {
                    continuation.resume(returning: Data())
                    return
                }
                // The handler captures the lock-guarded state, never the
                // reader: the handle keeps the closure alive, so a strong
                // self would close a retain cycle, and the state outlives
                // the reader exactly as long as the pipe does.
                handle.readabilityHandler = { [state] readable in
                    let chunk = readable.availableData
                    if chunk.isEmpty {
                        Self.finish(readable, state: state)
                    } else {
                        state.withLock { $0.data.append(chunk) }
                    }
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
        handle.readabilityHandler = nil
        let continuation = state.withLock { state -> CheckedContinuation<Data, Never>? in
            let pending = state.continuation
            state.continuation = nil
            return pending
        }
        continuation?.resume(returning: state.withLock { $0.data })
    }
}
