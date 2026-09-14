import Foundation
import HTTPTypes
import LittleSwitchCommon
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Traffic log model")
struct TrafficLogTests {
    @Test("Known credential headers are masked case-insensitively")
    func redactsHeaders() throws {
        let customKey = try #require(HTTPField.Name("X-Custom-API-Key"))
        let signature = try #require(HTTPField.Name("X-Signature"))
        let safe = try #require(HTTPField.Name("anthropic-beta"))
        let fields: HTTPFields = [
            .authorization: "Bearer incoming",
            .cookie: "session=private",
            customKey: "provider-key",
            signature: "signed-secret",
            safe: "tools-2026",
        ]

        let redacted = TrafficRedactor.headers(fields)

        #expect(value("authorization", in: redacted) == TrafficRedactor.mask)
        #expect(value("cookie", in: redacted) == TrafficRedactor.mask)
        #expect(value("x-custom-api-key", in: redacted) == TrafficRedactor.mask)
        #expect(value("x-signature", in: redacted) == TrafficRedactor.mask)
        #expect(value("anthropic-beta", in: redacted) == "tools-2026")

        let nio = HTTPHeaders([
            ("Proxy-Authorization", "proxy-secret"),
            ("Set-Cookie", "private=1"),
            ("X-Auth-Token", "token-secret"),
            ("X-Client-Secret", "client-secret"),
            ("X-Password", "password"),
            ("X-Credential", "credential"),
            ("Content-Type", "application/json"),
        ])
        let redactedNIO = TrafficRedactor.headers(nio)
        #expect(value("proxy-authorization", in: redactedNIO) == TrafficRedactor.mask)
        #expect(value("set-cookie", in: redactedNIO) == TrafficRedactor.mask)
        #expect(value("x-auth-token", in: redactedNIO) == TrafficRedactor.mask)
        #expect(value("x-client-secret", in: redactedNIO) == TrafficRedactor.mask)
        #expect(value("x-password", in: redactedNIO) == TrafficRedactor.mask)
        #expect(value("x-credential", in: redactedNIO) == TrafficRedactor.mask)
        #expect(value("content-type", in: redactedNIO) == "application/json")
    }

    @Test("Sensitive URL query values and user info never enter records")
    func redactsURLs() {
        let raw =
            "https://user:password@example.com/v1/messages?model=glm&api_key=one&signature=two&safe=yes#private"
        let redacted = TrafficRedactor.url(raw)

        #expect(
            redacted
                == "https://example.com/v1/messages?model=glm&api_key=%3Credacted%3E&signature=%3Credacted%3E&safe=yes"
        )
        #expect(redacted.contains("model=glm"))
        #expect(redacted.contains("safe=yes"))
        #expect(redacted.contains("api_key=%3Credacted%3E"))
        #expect(redacted.contains("signature=%3Credacted%3E"))
        #expect(!redacted.contains("user"))
        #expect(!redacted.contains("password"))
        #expect(!redacted.contains("private"))
        #expect(TrafficRedactor.url("not a URL") == TrafficRedactor.invalidURL)
        #expect(TrafficRedactor.url("https://") == TrafficRedactor.invalidURL)
        #expect(TrafficRedactor.url("mailto:user@example.com") == TrafficRedactor.invalidURL)
    }

    @Test("One event reduces complete request retry and response history")
    func reducesLifecycle() throws {
        let eventID = UUID()
        let providerID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let finishedAt = Date(timeIntervalSince1970: 101)
        let claudeBody = Data(#"{"model":"claude-opus-5","secret":"body stays complete"}"#.utf8)
        let firstBody = Data("unsupported image".utf8)
        let finalChunks = [Data("data: one\n\n".utf8), Data([0x00, 0xFF])]
        let actions: [TrafficAction] = [
            .started(
                TrafficRequestStart(
                    startedAt: startedAt,
                    method: "POST",
                    path: "/v1/messages",
                    headers: [TrafficHeader(name: "authorization", value: "<redacted>")]
                )
            ),
            .claudeRequestBody(claudeBody),
            routedTrafficAction(providerID: providerID),
            .upstreamRequest(
                TrafficUpstreamRequest(
                    attempt: 0,
                    claudeRoute: "claude-opus-5",
                    providerID: providerID,
                    providerName: "z.ai",
                    modelID: "glm",
                    url: "https://api.z.ai/v1/messages",
                    headers: [],
                    body: Data(#"{"model":"glm"}"#.utf8),
                    streaming: true
                )
            ),
            .upstreamResponseHead(
                TrafficUpstreamResponseHead(attempt: 0, status: 400, headers: [])
            ),
            .upstreamResponseChunk(
                TrafficUpstreamResponseChunk(attempt: 0, bytes: firstBody)
            ),
            .imageRetry,
            .upstreamRequest(
                TrafficUpstreamRequest(
                    attempt: 1,
                    claudeRoute: "claude-opus-5",
                    providerID: providerID,
                    providerName: "z.ai",
                    modelID: "glm",
                    url: "https://api.z.ai/v1/messages",
                    headers: [],
                    body: Data(#"{"model":"glm","image":"omitted"}"#.utf8),
                    streaming: true
                )
            ),
            .upstreamResponseHead(
                TrafficUpstreamResponseHead(
                    attempt: 1,
                    status: 200,
                    headers: [TrafficHeader(name: "content-type", value: "text/event-stream")]
                )
            ),
            .upstreamResponseChunk(
                TrafficUpstreamResponseChunk(attempt: 1, bytes: finalChunks[0])
            ),
            .upstreamResponseChunk(
                TrafficUpstreamResponseChunk(attempt: 1, bytes: finalChunks[1])
            ),
            .clientResponseHead(TrafficClientResponseHead(status: 200, headers: [])),
            .clientResponseChunk(finalChunks[0]),
            .clientResponseChunk(finalChunks[1]),
            .completed(TrafficCompletion(status: 200, finishedAt: finishedAt)),
        ]

        var event: TrafficEvent?
        for (sequence, action) in actions.enumerated() {
            let record = TrafficRecord(
                eventID: eventID,
                sequence: UInt64(sequence),
                timestamp: startedAt,
                action: action
            )
            if event == nil {
                event = TrafficEvent(firstRecord: record)
            } else {
                event?.apply(record)
            }
        }
        let reduced = try #require(event)

        #expect(reduced.id == eventID)
        expectTrafficRoute(reduced, providerID: providerID)
        #expect(reduced.claudeRequest.body == claudeBody)
        #expect(reduced.upstreamExchanges.count == 2)
        #expect(reduced.upstreamExchanges[0].response.body == firstBody)
        #expect(reduced.upstreamExchanges[1].response.body == finalChunks.reduce(Data(), +))
        #expect(reduced.clientResponse.body == finalChunks.reduce(Data(), +))
        #expect(reduced.didRetryImages)
        #expect(reduced.streaming)
        #expect(reduced.lifecycle == .completed)
        #expect(reduced.finalStatus == 200)
        #expect(reduced.finishedAt == finishedAt)
        #expect(!reduced.retentionTruncated)
        #expect(reduced.requestBytes == claudeBody.count)
        #expect(reduced.responseBytes == finalChunks.reduce(0) { $0 + $1.count })
        #expect(reduced.duration == 1)
    }

    @Test("A retained suffix is marked partial and terminal failures round trip")
    func partialFailureAndCodable() throws {
        let eventID = UUID()
        let timestamp = Date(timeIntervalSince1970: 200)
        let failure = TrafficFailure(kind: "provider", message: "Provider request failed")
        let records = [
            TrafficRecord(
                eventID: eventID,
                sequence: 3,
                timestamp: timestamp,
                action: .clientResponseChunk(Data("partial".utf8))
            ),
            TrafficRecord(
                eventID: eventID,
                sequence: 5,
                timestamp: timestamp,
                action: .failed(
                    TrafficFailureCompletion(
                        status: 502,
                        finishedAt: timestamp,
                        failure: failure
                    )
                )
            ),
        ]
        var event = TrafficEvent(firstRecord: records[0])
        event.apply(records[1])

        #expect(event.retentionTruncated)
        #expect(event.lifecycle == .failed)
        #expect(event.failure == failure)
        #expect(event.finalStatus == 502)

        let encoded = try JSONEncoder().encode(records)
        #expect(try JSONDecoder().decode([TrafficRecord].self, from: encoded) == records)

        let cancelled = TrafficRecord(
            eventID: UUID(),
            sequence: 0,
            timestamp: timestamp,
            action: .cancelled(finishedAt: timestamp)
        )
        let cancelledEvent = TrafficEvent(firstRecord: cancelled)
        #expect(cancelledEvent.lifecycle == .cancelled)
        #expect(cancelledEvent.finishedAt == timestamp)
        #expect(cancelledEvent.retentionTruncated)
    }
}

private func routedTrafficAction(providerID: UUID) -> TrafficAction {
    .routed(
        TrafficRoute(
            client: .claude,
            modelIdentifier: "claude-opus-5",
            target: TrafficRouteTarget(
                providerID: providerID,
                providerName: "z.ai",
                modelID: "glm"
            ),
            streaming: true
        )
    )
}

private func expectTrafficRoute(_ event: TrafficEvent, providerID: UUID) {
    #expect(event.client == .claude)
    #expect(event.claudeRoute == "claude-opus-5")
    #expect(event.providerID == providerID)
    #expect(event.providerName == "z.ai")
    #expect(event.modelID == "glm")
}

extension TrafficLogTests {
    @Test("Orphan actions and foreign records stay explicit")
    func reducerBoundaries() throws {
        let eventID = UUID()
        let timestamp = Date(timeIntervalSince1970: 300)
        let orphanHead = TrafficRecord(
            eventID: eventID,
            sequence: 0,
            timestamp: timestamp,
            action: .upstreamResponseHead(
                TrafficUpstreamResponseHead(attempt: 7, status: 503, headers: [])
            )
        )
        var event = TrafficEvent(firstRecord: orphanHead)

        #expect(event.retentionTruncated)
        #expect(event.upstreamExchanges.count == 1)
        #expect(event.upstreamExchanges[0].id == 7)
        #expect(event.upstreamExchanges[0].request == nil)
        #expect(event.upstreamExchanges[0].responseStatus == 503)

        let stateBeforeForeignRecord = event
        event.apply(
            TrafficRecord(
                eventID: UUID(),
                sequence: 1,
                timestamp: timestamp,
                action: .clientResponseChunk(Data("foreign".utf8))
            )
        )
        #expect(event == stateBeforeForeignRecord)

        let completedAt = timestamp.addingTimeInterval(1)
        event.apply(
            TrafficRecord(
                eventID: eventID,
                sequence: 1,
                timestamp: timestamp,
                action: .completed(TrafficCompletion(status: 204, finishedAt: completedAt))
            )
        )
        #expect(event.lifecycle == .completed)
        #expect(event.finalStatus == 204)
        #expect(event.finishedAt == completedAt)
    }

    @Test("The first terminal action wins for every later terminal permutation")
    func terminalActionsAreImmutable() {
        let timestamp = Date(timeIntervalSince1970: 350)
        let failure = TrafficFailure(kind: "provider", message: "Unavailable")
        let actions: [TrafficAction] = [
            .completed(
                TrafficCompletion(status: 204, finishedAt: timestamp.addingTimeInterval(1))
            ),
            .failed(
                TrafficFailureCompletion(
                    status: 502,
                    finishedAt: timestamp.addingTimeInterval(2),
                    failure: failure
                )
            ),
            .cancelled(finishedAt: timestamp.addingTimeInterval(3)),
        ]

        for firstAction in actions {
            let eventID = UUID()
            var event = TrafficEvent(
                firstRecord: TrafficRecord(
                    eventID: eventID,
                    sequence: 0,
                    timestamp: timestamp,
                    action: .started(
                        TrafficRequestStart(
                            startedAt: timestamp,
                            method: "POST",
                            path: "/v1/messages",
                            headers: []
                        )
                    )
                )
            )
            event.apply(
                TrafficRecord(
                    eventID: eventID,
                    sequence: 1,
                    timestamp: timestamp,
                    action: firstAction
                )
            )
            let established = TrafficTerminalState(event)
            #expect(!event.retentionTruncated)

            var continued = event
            continued.apply(
                TrafficRecord(
                    eventID: eventID,
                    sequence: 2,
                    timestamp: timestamp,
                    action: .clientResponseChunk(Data("x".utf8))
                )
            )
            #expect(TrafficTerminalState(continued) == established)
            #expect(continued.responseBytes == 1)
            #expect(!continued.retentionTruncated)

            for duplicateAction in actions {
                var duplicate = event
                duplicate.apply(
                    TrafficRecord(
                        eventID: eventID,
                        sequence: 2,
                        timestamp: timestamp,
                        action: duplicateAction
                    )
                )
                #expect(TrafficTerminalState(duplicate) == established)
                #expect(duplicate.retentionTruncated)
            }
        }
    }

    @Test("Sequence accounting follows the producer's UInt64 saturation")
    func sequenceSaturationBoundary() {
        let eventID = UUID()
        let timestamp = Date(timeIntervalSince1970: 400)
        var event = TrafficEvent(
            firstRecord: TrafficRecord(
                eventID: eventID,
                sequence: UInt64.max,
                timestamp: timestamp,
                action: .started(
                    TrafficRequestStart(
                        startedAt: timestamp,
                        method: "POST",
                        path: "/v1/messages",
                        headers: []
                    )
                )
            )
        )
        event.retentionTruncated = false

        event.apply(
            TrafficRecord(
                eventID: eventID,
                sequence: UInt64.max,
                timestamp: timestamp,
                action: .clientResponseChunk(Data("ok".utf8))
            )
        )

        #expect(!event.retentionTruncated)
        #expect(event.responseBytes == 2)

        var wrapped = event
        wrapped.retentionTruncated = false
        wrapped.apply(
            TrafficRecord(
                eventID: eventID,
                sequence: 0,
                timestamp: timestamp,
                action: .clientResponseChunk(Data("no".utf8))
            )
        )
        #expect(wrapped.retentionTruncated)
        #expect(wrapped.responseBytes == 4)
    }

    @Test("The no-op recorder accepts every action without side effects")
    func noopRecorder() {
        let recorder: any TrafficRecording = NoopTrafficRecorder()
        // Started, completed, and every mixed action must be accepted without
        // throwing; the no-op recorder discards data by design.
        let eventID = UUID()
        recorder.record(
            eventID: eventID,
            action: .started(
                TrafficRequestStart(
                    startedAt: Date(timeIntervalSince1970: 0),
                    method: "GET",
                    path: "/health",
                    headers: []
                )
            )
        )
        recorder.record(eventID: eventID, action: .claudeRequestBody(Data("test".utf8)))
        recorder.record(eventID: eventID, action: .cancelled(finishedAt: Date(timeIntervalSince1970: 1)))
    }

    private func value(_ name: String, in headers: [TrafficHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct TrafficTerminalState: Equatable {
    let lifecycle: TrafficLifecycle
    let finalStatus: Int?
    let finishedAt: Date?
    let failure: TrafficFailure?

    init(_ event: TrafficEvent) {
        lifecycle = event.lifecycle
        finalStatus = event.finalStatus
        finishedAt = event.finishedAt
        failure = event.failure
    }
}
