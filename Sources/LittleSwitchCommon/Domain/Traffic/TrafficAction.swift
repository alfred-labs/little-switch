import Foundation

public enum TrafficAction: Codable, Equatable, Sendable {
    case started(TrafficRequestStart)
    case claudeRequestBody(Data)
    case routed(TrafficRoute)
    case upstreamRequest(TrafficUpstreamRequest)
    case upstreamResponseHead(TrafficUpstreamResponseHead)
    case upstreamResponseChunk(TrafficUpstreamResponseChunk)
    case imageRetry
    case initialUsageEstimate(TrafficInitialUsageEstimate)
    case webSearch(TrafficWebSearch)
    case annotation(TrafficAnnotation)
    case clientResponseHead(TrafficClientResponseHead)
    case clientResponseChunk(Data)
    case completed(TrafficCompletion)
    case failed(TrafficFailureCompletion)
    case cancelled(finishedAt: Date)
}
