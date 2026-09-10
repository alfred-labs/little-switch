import Foundation
import HTTPTypes
import NIOHTTP1

public struct TrafficHeader: Codable, Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct TrafficPayload: Codable, Equatable, Sendable {
    public var headers: [TrafficHeader]
    public var body: Data

    public init(headers: [TrafficHeader] = [], body: Data = Data()) {
        self.headers = headers
        self.body = body
    }
}

public struct TrafficInitialUsageEstimate: Codable, Equatable, Sendable {
    public var tokenCount: Int
    public var source: TrafficInitialUsageEstimateSource
    public var providerOutcome: TrafficProviderCountOutcome
    public var elapsedMilliseconds: Int

    public init(
        tokenCount: Int,
        source: TrafficInitialUsageEstimateSource,
        providerOutcome: TrafficProviderCountOutcome,
        elapsedMilliseconds: Int
    ) {
        self.tokenCount = tokenCount
        self.source = source
        self.providerOutcome = providerOutcome
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public struct TrafficRequestStart: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var method: String
    public var path: String
    public var headers: [TrafficHeader]

    public init(
        startedAt: Date,
        method: String,
        path: String,
        headers: [TrafficHeader]
    ) {
        self.startedAt = startedAt
        self.method = method
        self.path = path
        self.headers = headers
    }
}

public struct TrafficRouteTarget: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var providerName: String
    public var modelID: String

    public init(providerID: UUID, providerName: String, modelID: String) {
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
    }
}

public struct TrafficRoute: Codable, Equatable, Sendable {
    public var client: GatewayClient
    public var modelIdentifier: String
    public var target: TrafficRouteTarget
    public var streaming: Bool

    public init(
        client: GatewayClient,
        modelIdentifier: String,
        target: TrafficRouteTarget,
        streaming: Bool
    ) {
        self.client = client
        self.modelIdentifier = modelIdentifier
        self.target = target
        self.streaming = streaming
    }
}

public struct TrafficUpstreamRequest: Codable, Equatable, Sendable {
    public var attempt: Int
    public var claudeRoute: String
    public var providerID: UUID
    public var providerName: String
    public var modelID: String
    public var url: String
    public var headers: [TrafficHeader]
    public var body: Data
    public var streaming: Bool

    public init(
        attempt: Int,
        claudeRoute: String,
        providerID: UUID,
        providerName: String,
        modelID: String,
        url: String,
        headers: [TrafficHeader],
        body: Data,
        streaming: Bool
    ) {
        self.attempt = attempt
        self.claudeRoute = claudeRoute
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.url = url
        self.headers = headers
        self.body = body
        self.streaming = streaming
    }
}

public struct TrafficUpstreamExchange: Codable, Equatable, Sendable, Identifiable {
    public var attempt: Int
    public var request: TrafficUpstreamRequest?
    public var responseStatus: Int?
    public var response: TrafficPayload

    public var id: Int { attempt }

    public init(
        attempt: Int,
        request: TrafficUpstreamRequest? = nil,
        responseStatus: Int? = nil,
        response: TrafficPayload = TrafficPayload()
    ) {
        self.attempt = attempt
        self.request = request
        self.responseStatus = responseStatus
        self.response = response
    }
}

public struct TrafficUpstreamResponseHead: Codable, Equatable, Sendable {
    public var attempt: Int
    public var status: Int
    public var headers: [TrafficHeader]

    public init(attempt: Int, status: Int, headers: [TrafficHeader]) {
        self.attempt = attempt
        self.status = status
        self.headers = headers
    }
}

public struct TrafficUpstreamResponseChunk: Codable, Equatable, Sendable {
    public var attempt: Int
    public var bytes: Data

    public init(attempt: Int, bytes: Data) {
        self.attempt = attempt
        self.bytes = bytes
    }
}

public struct TrafficClientResponseHead: Codable, Equatable, Sendable {
    public var status: Int
    public var headers: [TrafficHeader]

    public init(status: Int, headers: [TrafficHeader]) {
        self.status = status
        self.headers = headers
    }
}

public struct TrafficCompletion: Codable, Equatable, Sendable {
    public var status: Int
    public var finishedAt: Date

    public init(status: Int, finishedAt: Date) {
        self.status = status
        self.finishedAt = finishedAt
    }
}

public struct TrafficFailureCompletion: Codable, Equatable, Sendable {
    public var status: Int?
    public var finishedAt: Date
    public var failure: TrafficFailure

    public init(status: Int?, finishedAt: Date, failure: TrafficFailure) {
        self.status = status
        self.finishedAt = finishedAt
        self.failure = failure
    }
}

/// A non-terminal observation recorded on an in-flight request: something
/// was adjusted or dropped before dispatch, worth naming in the log without
/// deciding the request's lifecycle, failure surface, or usage outcome.
public struct TrafficAnnotation: Codable, Equatable, Sendable {
    public var kind: String
    public var message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

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

public struct TrafficRecord: Codable, Equatable, Sendable {
    public var eventID: UUID
    public var sequence: UInt64
    public var timestamp: Date
    public var action: TrafficAction

    public init(
        eventID: UUID,
        sequence: UInt64,
        timestamp: Date,
        action: TrafficAction
    ) {
        self.eventID = eventID
        self.sequence = sequence
        self.timestamp = timestamp
        self.action = action
    }
}

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

public protocol TrafficRecording: Sendable {
    func record(eventID: UUID, action: TrafficAction)
}

public struct NoopTrafficRecorder: TrafficRecording {
    public init() {}

    public func record(eventID: UUID, action: TrafficAction) {
        _ = eventID
        _ = action
    }
}

public enum TrafficRedactor {
    public static let mask = "<redacted>"
    public static let invalidURL = "<invalid-url>"

    public static func headers(_ fields: HTTPFields) -> [TrafficHeader] {
        fields.map { field in
            header(name: field.name.rawName, value: field.value)
        }
    }

    public static func headers(_ fields: HTTPHeaders) -> [TrafficHeader] {
        fields.map { name, value in
            header(name: name, value: value)
        }
    }

    public static func url(_ value: String) -> String {
        guard var components = URLComponents(string: value),
            components.scheme != nil,
            components.host?.isEmpty == false
        else {
            return invalidURL
        }
        components.user = nil
        components.password = nil
        components.fragment = nil
        components.queryItems = components.queryItems?.map { item in
            URLQueryItem(
                name: item.name,
                value: isSensitive(item.name) ? mask : item.value
            )
        }
        return components.description
    }

    private static func header(name: String, value: String) -> TrafficHeader {
        TrafficHeader(name: name, value: isSensitive(name) ? mask : value)
    }

    private static func isSensitive(_ name: String) -> Bool {
        let normalized = name.lowercased().filter(\.isLetter)
        return normalized.contains("authorization")
            || normalized.contains("apikey")
            || normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.contains("credential")
            || normalized.contains("signature")
            || normalized == "cookie"
            || normalized == "setcookie"
    }
}
