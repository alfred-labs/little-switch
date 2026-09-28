package struct ResponsesWebSocketLimits: Sendable {
    package var connectionLifetimeSeconds: Int64 = 3_600
    package var closeGraceSeconds: Int64 = 5
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
