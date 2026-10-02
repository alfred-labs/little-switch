/// Connection-wide payload counters exclude HTTP, control frames and framing
/// overhead. A successful local write does not prove peer receipt or acceptance.
/// Counters measure wire payload after optional compression, not logical message
/// sizes. Negotiation can still leave individual messages uncompressed. Compare
/// snapshots to obtain per-exchange deltas.
package struct UpstreamWebSocketDiagnostics: Sendable {
    package enum Compression: String, Sendable {
        case none
        case perMessageDeflate = "permessage-deflate"
    }

    package enum CloseOrigin: String, Sendable {
        case peer
        case local
    }

    package var writtenPayloadBytes: UInt64 = 0
    package var receivedPayloadBytes: UInt64 = 0
    package var writtenDataFrames: UInt64 = 0
    package var receivedDataFrames: UInt64 = 0
    package var compression: Compression = .none
    /// Nil means no observed close frame, not a claim that the peer disconnected.
    package var closeOrigin: CloseOrigin?
    package var peerCloseCode: UInt16?
    package var localCloseCode: UInt16?
    /// In-memory only. Consumers must classify by type/code, never serialize or
    /// interpolate arbitrary error descriptions, associated values or user info.
    package var underlyingError: (any Error)?

    package init() {}
}
