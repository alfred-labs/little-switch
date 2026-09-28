public struct UpstreamWebSocketConfiguration: Sendable {
    public let handshakeTimeout: Duration
    public let rejectionBodyTimeout: Duration
    public let closeTimeout: Duration
    public let maximumHeaderBytes: Int
    public let maximumHeaderFieldBytes: Int
    public let maximumHeaderCount: Int
    public let maximumRejectionBodyBytes: Int
    public let maximumInboundMessageBytes: Int
    public let maximumOutboundMessageBytes: Int
    public let outboundFragmentBytes: Int
    public let maximumQueuedMessages: Int
    public let maximumQueuedBytes: Int
    public let pingInterval: Duration?

    public init(
        handshakeTimeout: Duration = .seconds(30),
        rejectionBodyTimeout: Duration = .seconds(2),
        closeTimeout: Duration = .seconds(5),
        maximumHeaderBytes: Int = 64 * 1_024,
        maximumHeaderFieldBytes: Int = 16 * 1_024,
        maximumHeaderCount: Int = 128,
        maximumRejectionBodyBytes: Int = 64 * 1_024,
        maximumInboundMessageBytes: Int = 8 * 1_024 * 1_024,
        maximumOutboundMessageBytes: Int = 64 * 1_024 * 1_024,
        outboundFragmentBytes: Int = 16 * 1_024,
        maximumQueuedMessages: Int = 128,
        maximumQueuedBytes: Int = 64 * 1_024 * 1_024,
        pingInterval: Duration? = nil
    ) {
        self.handshakeTimeout = handshakeTimeout
        self.rejectionBodyTimeout = rejectionBodyTimeout
        self.closeTimeout = closeTimeout
        self.maximumHeaderBytes = maximumHeaderBytes
        self.maximumHeaderFieldBytes = maximumHeaderFieldBytes
        self.maximumHeaderCount = maximumHeaderCount
        self.maximumRejectionBodyBytes = maximumRejectionBodyBytes
        self.maximumInboundMessageBytes = maximumInboundMessageBytes
        self.maximumOutboundMessageBytes = maximumOutboundMessageBytes
        self.outboundFragmentBytes = outboundFragmentBytes
        self.maximumQueuedMessages = maximumQueuedMessages
        self.maximumQueuedBytes = maximumQueuedBytes
        self.pingInterval = pingInterval
    }

    func validate() throws {
        let durations = [handshakeTimeout, rejectionBodyTimeout, closeTimeout] + (pingInterval.map { [$0] } ?? [])
        let limits = [
            maximumHeaderBytes, maximumHeaderFieldBytes, maximumHeaderCount, maximumRejectionBodyBytes,
            maximumInboundMessageBytes, maximumOutboundMessageBytes, outboundFragmentBytes,
            maximumQueuedMessages, maximumQueuedBytes,
        ]
        guard durations.allSatisfy({ $0 > .zero && $0 < .seconds(Int64.max / 1_000_000_000) }),
            limits.allSatisfy({ $0 > 0 }),
            maximumHeaderFieldBytes <= maximumHeaderBytes,
            maximumHeaderCount < Int(UInt16.max),
            maximumInboundMessageBytes <= Int(UInt32.max),
            outboundFragmentBytes <= maximumOutboundMessageBytes
        else { throw UpstreamWebSocketFailure(kind: .invalidConfiguration) }
    }
}
