import Foundation
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring bounded response failure observer")
struct MonitoringResponseFailureObserverTests {
    @Test("Fragmented SSE line endings and multiline data preserve one terminal", arguments: ["\n", "\r", "\r\n"])
    func lineEndings(separator: String) {
        let lines = ["", ": ignored", "event:error", "data:{\"type\":\"error\",", "data: \"error\":{}}", "", ""]
        let stream = lines.joined(separator: separator)
        var observer = MonitoringResponseFailureObserver()
        var failures = 0
        for byte in stream.utf8 where observer.append(.init(bytes: [byte])) {
            failures += 1
        }
        #expect(failures == 1)
        #expect(observer.pending.isEmpty)
        #expect(observer.linePrefix.isEmpty)
        let repeatedFailure = observer.append(.init(string: Self.failure))
        #expect(!repeatedFailure)
    }

    @Test("An absent event name uses only recognized JSON discriminators")
    func dataOnly() {
        let frames = [
            "data: {\"type\":\"error\",\"error\":{\"message\":\"PRIVATE_ERROR\"}}\n\n",
            "data: {\"type\":\"error\",\"code\":null,\"message\":\"PRIVATE_ERROR\",\"param\":null}\n\n",
            "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"error\":null}}\n\n",
        ]
        for frame in frames {
            var observer = MonitoringResponseFailureObserver()
            let observedFailure = observer.append(.init(string: frame))
            #expect(observedFailure)
        }
    }

    @Test("Failure detection follows Foundation decoding of otherwise recognizable envelopes")
    func foundationSyntaxTolerance() {
        var observer = MonitoringResponseFailureObserver()
        let recognizedFailure = observer.append(.init(string: "data: {\"type\":\"error\",\"error\":{},}\n\n"))
        #expect(recognizedFailure)
    }

    @Test("The final explicit event field wins and unknown names cannot impersonate a failure")
    func eventIdentity() {
        let bodies = [
            "event: error\nevent: notice\ndata: {\"type\":\"error\",\"error\":{}}\n\n",
            "event: unspecified\ndata: {\"type\":\"error\",\"error\":{}}\n\n",
            "event: error" + String(repeating: "x", count: 80) + "\ndata: {\"type\":\"error\",\"error\":{}}\n\n",
            "event: response.failed\ndata: {\"type\":\"error\",\"error\":{}}\n\n",
            "event: error\ndata: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\"}}\n\n",
        ]
        for body in bodies {
            var observer = MonitoringResponseFailureObserver()
            let unrelatedFailure = observer.append(.init(string: body))
            #expect(!unrelatedFailure)
            let followingFailure = observer.append(.init(string: Self.failure))
            #expect(followingFailure)
        }
    }

    @Test(
        "Empty and explicit message event names retain data-only failure detection and replace the previous name",
        arguments: ["event", "event:", "event: ", "event: message"],
        ["", "event: error\n", "event: response.failed\n", "event: notice\n"])
    func defaultEventNames(field: String, previous: String) {
        let envelopes = [
            "{\"type\":\"error\",\"error\":{}}",
            "{\"type\":\"response.failed\",\"response\":{\"status\":\"failed\"}}",
        ]
        for envelope in envelopes {
            var observer = MonitoringResponseFailureObserver()
            let stream = previous + field + "\ndata: " + envelope + "\n\n"
            var failures = 0
            for byte in stream.utf8 where observer.append(.init(bytes: [byte])) {
                failures += 1
            }
            #expect(failures == 1)
            #expect(observer.pending.isEmpty)
            #expect(observer.linePrefix.isEmpty)
        }
    }

    @Test("Valueless data and unknown fields cannot invent a failure and the next frame still works")
    func fieldsWithoutColons() {
        var observer = MonitoringResponseFailureObserver()
        let frames = [
            "event: error\ndata\ncomment without a colon\n\n",
            "data\ncomment without a colon\n\n",
            Self.failure,
            Self.failure,
        ]
        var failures: [Bool] = []
        for frame in frames {
            failures.append(observer.append(.init(string: frame)))
        }
        #expect(failures == [false, false, true, false])
        #expect(observer.pending.isEmpty)
        #expect(observer.linePrefix.isEmpty)
    }

    @Test("Malformed, incomplete and unrelated payloads cannot become an observed failure")
    func malformedFrames() {
        let bodies = [
            "data: [DONE]\n\n",
            "event: error\ndata\n\n",
            "event: error\ndata: {\"type\":\"error\",\"error\":}\n\n",
            "data: {\"type\":\"error\",\"error\":false}\n\n",
            "data: {\"type\":\"message\",\"error\":{}}\n\n",
            "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"incomplete\"}}\n\n",
            "data: {}\n\n",
            "data: {\"type\":\"error\",\"error\":{}}",
        ]
        for body in bodies {
            var observer = MonitoringResponseFailureObserver()
            let observedFailure = observer.append(.init(string: body))
            #expect(!observedFailure)
        }
        var observer = MonitoringResponseFailureObserver()
        let invalidUTF8 =
            Data("data: {\"type\":\"error\",\"error\":{\"message\":\"".utf8)
            + Data([255]) + Data("\"}}\n\n".utf8)
        let malformedFailure = observer.append(.init(bytes: invalidUTF8))
        #expect(!malformedFailure)
        let followingFailure = observer.append(.init(string: Self.failure))
        #expect(followingFailure)
    }

    @Test("The payload and line prefix remain bounded even when the explicit event follows a huge payload")
    func retainedBounds() {
        for limit in [0, 1, 32, 128] {
            var observer = MonitoringResponseFailureObserver(maximumFrameBytes: limit)
            let stream =
                "data: {\"type\":\"response.failed\",\"response\":{\"output\":\""
                + String(repeating: "x", count: 100_000) + "\"}}\nevent: response.failed\n\n"
            var failures = 0
            let bytes = Data(stream.utf8)
            for offset in stride(from: 0, to: bytes.count, by: 127) {
                if observer.append(.init(bytes: bytes.dropFirst(offset).prefix(127))) { failures += 1 }
                #expect(observer.pending.count <= max(1, limit))
                #expect(observer.linePrefix.count <= 64)
            }
            #expect(failures == 1)
            #expect(observer.pending.isEmpty)
            #expect(observer.linePrefix.isEmpty)
        }
    }

    @Test("Data-only frames fit at the exact limit and oversized content recovers at the next boundary")
    func exactLimit() {
        let frame = "data: {\"type\":\"error\",\"error\":{}}\n"
        var exact = MonitoringResponseFailureObserver(maximumFrameBytes: frame.utf8.count)
        let fittingFailure = exact.append(.init(string: frame + "\n"))
        #expect(fittingFailure)
        var smaller = MonitoringResponseFailureObserver(maximumFrameBytes: frame.utf8.count - 1)
        let oversizedFailure = smaller.append(.init(string: frame + "\n"))
        #expect(!oversizedFailure)
        #expect(smaller.pending.isEmpty)
        let followingFailure = smaller.append(.init(string: Self.failure))
        #expect(followingFailure)
    }

    private static let failure = "event: error\ndata: {\"type\":\"error\",\"error\":{}}\n\n"
}
