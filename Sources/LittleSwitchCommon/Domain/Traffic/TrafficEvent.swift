import Foundation

public struct TrafficEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date?
    public var method: String
    public var path: String
    public var client: GatewayClient?
    public var claudeRoute: String?
    public var providerID: UUID?
    public var providerName: String?
    public var modelID: String?
    public var lifecycle: TrafficLifecycle
    public var finalStatus: Int?
    public var failure: TrafficFailure?
    public var streaming: Bool
    public var didRetryImages: Bool
    public var initialUsageEstimate: TrafficInitialUsageEstimate?
    public var annotations: [TrafficAnnotation]?
    public var claudeRequest: TrafficPayload
    public var clientResponse: TrafficPayload
    public var upstreamExchanges: [TrafficUpstreamExchange]
    public var webSearches: [TrafficWebSearch]
    public var retentionTruncated: Bool
    public var lastSequence: UInt64?

    public init(firstRecord: TrafficRecord) {
        id = firstRecord.eventID
        startedAt = firstRecord.timestamp
        finishedAt = nil
        method = "—"
        path = "Unknown request"
        client = nil
        claudeRoute = nil
        providerID = nil
        providerName = nil
        modelID = nil
        lifecycle = .inProgress
        finalStatus = nil
        failure = nil
        streaming = false
        didRetryImages = false
        initialUsageEstimate = nil
        annotations = nil
        claudeRequest = TrafficPayload()
        clientResponse = TrafficPayload()
        upstreamExchanges = []
        webSearches = []
        if case .started = firstRecord.action {
            retentionTruncated = firstRecord.sequence != 0
        } else {
            retentionTruncated = true
        }
        lastSequence = nil
        apply(firstRecord)
    }

    public var requestBytes: Int { claudeRequest.body.count }

    public var responseBytes: Int { clientResponse.body.count }

    public var duration: TimeInterval? {
        finishedAt?.timeIntervalSince(startedAt)
    }

    public mutating func apply(_ record: TrafficRecord) {
        guard record.eventID == id else {
            retentionTruncated = true
            return
        }
        if let lastSequence {
            let expectedSequence = lastSequence == .max ? UInt64.max : lastSequence + 1
            if record.sequence != expectedSequence {
                retentionTruncated = true
            }
        } else if record.sequence != 0 {
            retentionTruncated = true
        }
        self.lastSequence = record.sequence

        if lifecycle != .inProgress {
            switch record.action {
            case .completed, .failed, .cancelled:
                retentionTruncated = true
                return
            default:
                break
            }
        }

        switch record.action {
        case .started(let start):
            startedAt = start.startedAt
            method = start.method
            path = start.path
            claudeRequest.headers = start.headers
        case .claudeRequestBody(let body):
            claudeRequest.body = body
        case .routed(let route):
            client = route.client
            claudeRoute = route.modelIdentifier
            providerID = route.target.providerID
            providerName = route.target.providerName
            modelID = route.target.modelID
            streaming = route.streaming
        case .upstreamRequest, .upstreamResponseHead, .upstreamResponseChunk:
            applyUpstream(record.action)
        case .imageRetry:
            didRetryImages = true
        case .initialUsageEstimate(let estimate):
            initialUsageEstimate = estimate
        case .webSearch(let search):
            webSearches.append(search)
        case .annotation(let note):
            annotations = (annotations ?? []) + [note]
        case .clientResponseHead(let head):
            finalStatus = head.status
            clientResponse.headers = head.headers
        case .clientResponseChunk(let bytes):
            clientResponse.body.append(bytes)
        case .completed(let completion):
            lifecycle = .completed
            finalStatus = completion.status
            finishedAt = completion.finishedAt
        case .failed(let completion):
            lifecycle = .failed
            finalStatus = completion.status
            finishedAt = completion.finishedAt
            failure = completion.failure
        case .cancelled(let finishedAt):
            lifecycle = .cancelled
            self.finishedAt = finishedAt
        }
    }

    private mutating func applyUpstream(_ action: TrafficAction) {
        if case .upstreamRequest(let request) = action {
            apply(request)
        } else if case .upstreamResponseHead(let head) = action {
            let index = exchangeIndex(attempt: head.attempt, markMissing: true)
            upstreamExchanges[index].responseStatus = head.status
            upstreamExchanges[index].response.headers = head.headers
        } else if case .upstreamResponseChunk(let chunk) = action {
            let index = exchangeIndex(attempt: chunk.attempt, markMissing: true)
            upstreamExchanges[index].response.body.append(chunk.bytes)
        }
    }

    private mutating func apply(_ request: TrafficUpstreamRequest) {
        let index = exchangeIndex(attempt: request.attempt, markMissing: false)
        upstreamExchanges[index].request = request
        upstreamExchanges.sort { $0.attempt < $1.attempt }
        claudeRoute = request.claudeRoute
        providerID = request.providerID
        providerName = request.providerName
        modelID = request.modelID
        streaming = request.streaming
    }

    private mutating func exchangeIndex(attempt: Int, markMissing: Bool) -> Int {
        if let index = upstreamExchanges.firstIndex(where: { $0.attempt == attempt }) {
            return index
        }
        if markMissing {
            retentionTruncated = true
        }
        upstreamExchanges.append(TrafficUpstreamExchange(attempt: attempt))
        return upstreamExchanges.count - 1
    }
}
