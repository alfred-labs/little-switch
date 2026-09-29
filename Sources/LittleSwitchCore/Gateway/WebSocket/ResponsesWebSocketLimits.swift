package struct ResponsesWebSocketLimits: Sendable {
    package var connectionLifetimeSeconds: Int64 = 3_600
    package var closeGraceSeconds: Int64 = 5
    package var steeringAcknowledgementTimeout: Duration = .seconds(5)
    // Admission/queueing of the next generation may take much longer than an
    // acknowledgement. Allow one minute, still far below the socket lifetime.
    package var steeringContinuationTimeout: Duration = .seconds(60)
    package var maxFrameBytes = 64 * 1_024 * 1_024
    package var maxQueuedRequests = 128
    package var maxQueuedBytes = 64 * 1_024 * 1_024
    package var maxActiveResponses = 16
    package var maxNamedStreams = 32
    package var maxHistoryBytes = 128 * 1_024 * 1_024
    package var maxActiveBytes = 128 * 1_024 * 1_024
    package var maxResponseBytes = 8 * 1_024 * 1_024

    package init() {}
}
