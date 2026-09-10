import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

enum GatewayLiveFirstEvent: Equatable, Sendable {
    case responseReturned
    case upstreamRead
}

actor GatewayLiveResponseRace {
    private var firstEvent: GatewayLiveFirstEvent?
    private var waiters: [CheckedContinuation<GatewayLiveFirstEvent, Never>] = []

    func recordResponseReturned() {
        record(.responseReturned)
    }

    func recordUpstreamRead() {
        record(.upstreamRead)
    }

    func waitForFirstEvent() async -> GatewayLiveFirstEvent {
        if let firstEvent {
            return firstEvent
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func record(_ event: GatewayLiveFirstEvent) {
        guard firstEvent == nil else {
            return
        }
        firstEvent = event
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: event)
        }
    }
}

actor GatewayExecutionGate {
    private let entered = AsyncTestGate()
    private let released = AsyncTestGate()

    func enter() async throws {
        await entered.open()
        try await released.wait()
    }

    func waitUntilEntered() async throws {
        try await entered.wait(
            description: "the gateway transport execution gate"
        )
    }

    func release() async {
        await released.open()
    }
}

actor GatewayGatedBodyState {
    private let chunks: [ByteBuffer]
    private let gatedIndex: Int?
    private let responseRace: GatewayLiveResponseRace?
    private var index = 0
    private var released = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var readWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        chunks: [Data],
        gatedIndex: Int?,
        responseRace: GatewayLiveResponseRace?
    ) {
        self.chunks = chunks.map { ByteBuffer(bytes: $0) }
        self.gatedIndex = gatedIndex
        self.responseRace = responseRace
    }

    var readCount: Int {
        index
    }

    func next() async -> ByteBuffer? {
        guard index < chunks.count else {
            return nil
        }
        let currentIndex = index
        index += 1
        await responseRace?.recordUpstreamRead()
        resumeReadWaiters()
        if currentIndex == gatedIndex, !released {
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }
        return chunks[currentIndex]
    }

    func waitForReadCount(_ count: Int) async {
        guard index < count else {
            return
        }
        await withCheckedContinuation { continuation in
            readWaiters.append((count, continuation))
        }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    private func resumeReadWaiters() {
        var pending: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in readWaiters {
            if index >= waiter.0 {
                waiter.1.resume()
            } else {
                pending.append(waiter)
            }
        }
        readWaiters = pending
    }
}

struct GatewayGatedBody: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        let state: GatewayGatedBodyState

        mutating func next() async -> ByteBuffer? {
            await state.next()
        }
    }

    private let state: GatewayGatedBodyState

    init(
        chunks: [Data],
        gatedIndex: Int? = nil,
        responseRace: GatewayLiveResponseRace? = nil
    ) {
        state = GatewayGatedBodyState(
            chunks: chunks,
            gatedIndex: gatedIndex,
            responseRace: responseRace
        )
    }

    var readCount: Int {
        get async { await state.readCount }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(state: state)
    }

    func waitForReadCount(_ count: Int) async {
        await state.waitForReadCount(count)
    }

    func release() async {
        await state.release()
    }
}

enum GatewayLiveTransportStep: Sendable {
    case response(HTTPClientResponse)
    case gated(GatewayExecutionGate, HTTPClientResponse)
}

actor GatewayLiveTransport: UpstreamTransport {
    private var steps: [GatewayLiveTransportStep]
    private(set) var requests: [RecordedGatewayRequest] = []

    init(steps: [GatewayLiveTransportStep]) {
        self.steps = steps
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        var body = Data()
        if let requestBody = request.body {
            for try await buffer in requestBody {
                body.append(contentsOf: buffer.readableBytesView)
            }
        }
        requests.append(RecordedGatewayRequest(url: request.url, headers: request.headers, body: body))
        guard !steps.isEmpty else {
            throw GatewayTestError.failure
        }
        switch steps.removeFirst() {
        case .response(let response):
            return response
        // swiftlint:disable:next pattern_matching_keywords
        case .gated(let gate, let response):
            try await gate.enter()
            return response
        }
    }
}

actor GatewayLiveWriterProbe {
    private let blockingMarker: String
    private var data = Data()
    private var markerWaiters: [(String, CheckedContinuation<Void, Never>)] = []
    private var blockedWrite: CheckedContinuation<Void, Never>?
    private var blockedWriteReleased = false
    private(set) var finished = false

    init(blockingMarker: String) {
        self.blockingMarker = blockingMarker
    }

    var string: String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    func append(_ buffer: ByteBuffer) async {
        let chunk = Data(buffer.readableBytesView)
        data.append(chunk)
        resumeMarkerWaiters()
        guard !blockedWriteReleased,
            (String(bytes: chunk, encoding: .utf8) ?? "").contains(blockingMarker)
        else {
            return
        }
        await withCheckedContinuation { continuation in
            blockedWrite = continuation
        }
    }

    func waitUntilContains(_ marker: String) async {
        guard !string.contains(marker) else {
            return
        }
        await withCheckedContinuation { continuation in
            markerWaiters.append((marker, continuation))
        }
    }

    func releaseBlockedWrite() {
        blockedWriteReleased = true
        blockedWrite?.resume()
        blockedWrite = nil
    }

    func markFinished() {
        finished = true
    }

    private func resumeMarkerWaiters() {
        var pending: [(String, CheckedContinuation<Void, Never>)] = []
        for waiter in markerWaiters {
            if string.contains(waiter.0) {
                waiter.1.resume()
            } else {
                pending.append(waiter)
            }
        }
        markerWaiters = pending
    }
}

struct GatewayLiveResponseWriter: ResponseBodyWriter {
    let probe: GatewayLiveWriterProbe

    mutating func write(_ buffer: ByteBuffer) async throws {
        await probe.append(buffer)
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        _ = trailingHeaders
        await probe.markFinished()
    }
}

func gatewayStreamingResponse(
    _ sequence: GatewayGatedBody
) -> HTTPClientResponse {
    HTTPClientResponse(
        status: .ok,
        headers: ["content-type": "text/event-stream"],
        body: .stream(sequence)
    )
}

func searchedProviderTurnFrames() throws -> [ServerSentEventFrame] {
    var frames = try realisticProviderFrames()
    let terminalStart = frames.count - 3
    let ordinaryToolFrames = [
        try providerFrame(
            "content_block_start",
            [
                "type": "content_block_start",
                "index": 3,
                "content_block": [
                    "type": "tool_use",
                    "id": "weather_tool",
                    "name": "weather",
                    "input": [:],
                ],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 3,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": #"{"city":"Paris"}"#,
                ],
            ]
        ),
        try providerFrame("content_block_stop", ["type": "content_block_stop", "index": 3]),
    ]
    frames.insert(contentsOf: ordinaryToolFrames, at: terminalStart)
    return frames
}

func finalProviderTurnChunks() throws -> [Data] {
    let early = [
        try providerFrame(
            "message_start",
            [
                "type": "message_start",
                "message": providerMessage(id: "msg_final", inputTokens: 4),
            ]
        ),
        try providerFrame(
            "content_block_start",
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "text", "text": ""],
            ]
        ),
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "text_delta", "text": "FIRST"],
            ]
        ),
    ]
    let tail = [
        try providerFrame(
            "content_block_delta",
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "text_delta", "text": "SECOND"],
            ]
        ),
        try providerFrame("content_block_stop", ["type": "content_block_stop", "index": 0]),
        try providerFrame(
            "message_delta",
            [
                "type": "message_delta",
                "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
                "usage": ["output_tokens": 3],
            ]
        ),
        try providerFrame("message_stop", ["type": "message_stop"]),
    ]
    return [try gatewayProviderSSE(early), try gatewayProviderSSE(tail)]
}

func gatewayProviderSSE(
    _ frames: [ServerSentEventFrame]
) throws -> Data {
    var data = Data()
    for frame in frames {
        let event = try #require(frame.event)
        data.append(Data("event: \(event)\ndata: ".utf8))
        data.append(frame.data)
        data.append(Data("\n\n".utf8))
    }
    return data
}
