import Foundation
import NIOCore

/// Observes client-bound SSE without changing or retaining its wire payload.
/// A small transient frame supports data-only events. An explicit failure event
/// remains observable when its response/output or remote error text exceeds it.
package struct MonitoringResponseFailureObserver: Sendable {
    private enum Event {
        case error, responseFailed, message, other
    }

    private let maximumFrameBytes: Int
    private(set) var pending = Data()
    private(set) var linePrefix = Data()
    private var lineLength = 0
    private var followsCarriageReturn = false
    private var discarded = false
    private var event = Event.message
    private var hasData = false
    private var failed = false

    package init(maximumFrameBytes: Int = 16 * 1_024) {
        self.maximumFrameBytes = max(1, maximumFrameBytes)
    }

    /// Returns true once, on the first complete provider failure event.
    package mutating func append(_ buffer: ByteBuffer) -> Bool {
        guard !failed else { return false }
        for byte in buffer.readableBytesView {
            if byte == 10, followsCarriageReturn {
                followsCarriageReturn = false
                continue
            }
            followsCarriageReturn = byte == 13
            if byte == 10 || byte == 13 {
                if lineLength == 0 {
                    completeFrame()
                    if failed { return true }
                } else {
                    completeLine()
                    retain(10)
                }
            } else {
                lineLength = min(65, lineLength + 1)
                if linePrefix.count < 64 { linePrefix.append(byte) }
                retain(byte)
            }
        }
        return false
    }

    private mutating func retain(_ byte: UInt8) {
        guard !discarded else { return }
        guard pending.count < maximumFrameBytes else {
            discarded = true
            pending.removeAll(keepingCapacity: false)
            return
        }
        pending.append(byte)
    }

    private mutating func completeLine() {
        let colon = linePrefix.firstIndex(of: 58)
        let name = colon.map { linePrefix[..<$0] } ?? linePrefix
        if name.elementsEqual("data".utf8) { hasData = true }
        if name.elementsEqual("event".utf8) {
            var value = colon.map { linePrefix.suffix(from: $0 + 1) } ?? Data()
            if value.first == 32 { value = value.dropFirst() }
            if lineLength <= 64, value.isEmpty || value.elementsEqual("message".utf8) {
                event = .message
            } else if lineLength <= 64, value.elementsEqual("error".utf8) {
                event = .error
            } else if lineLength <= 64, value.elementsEqual("response.failed".utf8) {
                event = .responseFailed
            } else {
                event = .other
            }
        }
        linePrefix.removeAll(keepingCapacity: false)
        lineLength = 0
    }

    private mutating func completeFrame() {
        if discarded {
            failed = hasData && (event == .error || event == .responseFailed)
        } else if let envelope = MonitoringProviderFailureEnvelope.decode(frame: pending) {
            switch event {
            case .message: failed = envelope.isFailure
            case .error: failed = envelope.isError
            case .responseFailed: failed = envelope.isFailedResponse
            case .other: break
            }
        }
        pending.removeAll(keepingCapacity: false)
        discarded = false
        event = .message
        hasData = false
    }
}
