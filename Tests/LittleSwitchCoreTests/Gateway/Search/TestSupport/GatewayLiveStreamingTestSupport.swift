import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

enum StreamingFirstStage: Equatable, Sendable {
    case responseReturned
    case upstreamRead
}

actor StreamingStageRecorder {
    private let blockingMarker: String?
    private var firstStage: StreamingFirstStage?
    private var firstStageWaiters: [CheckedContinuation<StreamingFirstStage, Never>] = []
    private var markerWaiters: [(String, CheckedContinuation<Void, Never>)] = []
    private var blockedWrite: CheckedContinuation<Void, Never>?
    private var blockedWriteReleased = false
    private var writtenChunks: [Data] = []
    private(set) var finishCount = 0

    init(blockingMarker: String? = nil) {
        self.blockingMarker = blockingMarker
    }

    var body: Data {
        writtenChunks.reduce(into: Data()) { $0.append($1) }
    }

    var bodyString: String {
        String(bytes: body, encoding: .utf8) ?? ""
    }

    func responseReturned() {
        recordFirstStage(.responseReturned)
    }

    func upstreamRead() {
        recordFirstStage(.upstreamRead)
    }

    func waitForFirstStage() async -> StreamingFirstStage {
        if let firstStage {
            return firstStage
        }
        return await withCheckedContinuation { continuation in
            firstStageWaiters.append(continuation)
        }
    }

    func didWrite(_ data: Data) async throws {
        writtenChunks.append(data)
        resumeMarkerWaiters()
        guard let blockingMarker,
            !blockedWriteReleased,
            (String(bytes: data, encoding: .utf8) ?? "").contains(blockingMarker)
        else {
            return
        }
        await withCheckedContinuation { continuation in
            blockedWrite = continuation
        }
    }

    func didFinish(_ trailingHeaders: HTTPFields?) {
        _ = trailingHeaders
        finishCount += 1
    }

    func waitUntilContains(_ marker: String) async {
        guard !bodyString.contains(marker) else {
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

    private func recordFirstStage(_ stage: StreamingFirstStage) {
        guard firstStage == nil else {
            return
        }
        firstStage = stage
        let waiters = firstStageWaiters
        firstStageWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: stage)
        }
    }

    private func resumeMarkerWaiters() {
        var pending: [(String, CheckedContinuation<Void, Never>)] = []
        for waiter in markerWaiters {
            if bodyString.contains(waiter.0) {
                waiter.1.resume()
            } else {
                pending.append(waiter)
            }
        }
        markerWaiters = pending
    }
}

struct ObservingResponseBodyWriter: ResponseBodyWriter {
    let recorder: StreamingStageRecorder

    mutating func write(_ buffer: ByteBuffer) async throws {
        try await recorder.didWrite(Data(buffer.readableBytesView))
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        await recorder.didFinish(trailingHeaders)
    }
}

enum DemandTrackedBodyTermination: Sendable {
    case end
    case failure
    case cancellation
}

actor DemandTrackedBodyState {
    private let chunks: [ByteBuffer]
    private let gatedNextCall: Int?
    private let termination: DemandTrackedBodyTermination
    private let recorder: StreamingStageRecorder?
    private var index = 0
    private var gateReleased = false
    private var gateWaiter: CheckedContinuation<Void, Never>?
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        chunks: [Data],
        gatedNextCall: Int?,
        termination: DemandTrackedBodyTermination,
        recorder: StreamingStageRecorder?
    ) {
        self.chunks = chunks.map { ByteBuffer(bytes: $0) }
        self.gatedNextCall = gatedNextCall
        self.termination = termination
        self.recorder = recorder
    }

    var nextCallCount: Int {
        index
    }

    func next() async throws -> ByteBuffer? {
        let call = index
        index += 1
        await recorder?.upstreamRead()
        resumeCountWaiters()
        if gatedNextCall == call, !gateReleased {
            await withCheckedContinuation { continuation in
                gateWaiter = continuation
            }
        }
        if call < chunks.count {
            return chunks[call]
        }
        switch termination {
        case .end:
            return nil
        case .failure:
            throw GatewayTestError.privateFailure
        case .cancellation:
            throw CancellationError()
        }
    }

    func waitForNextCallCount(_ count: Int) async {
        guard index < count else {
            return
        }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func releaseGate() {
        gateReleased = true
        gateWaiter?.resume()
        gateWaiter = nil
    }

    private func resumeCountWaiters() {
        var pending: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in countWaiters {
            if index >= waiter.0 {
                waiter.1.resume()
            } else {
                pending.append(waiter)
            }
        }
        countWaiters = pending
    }
}

struct DemandTrackedBodySequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        let state: DemandTrackedBodyState

        mutating func next() async throws -> ByteBuffer? {
            try await state.next()
        }
    }

    private let state: DemandTrackedBodyState

    init(
        chunks: [Data],
        gatedNextCall: Int? = nil,
        termination: DemandTrackedBodyTermination = .end,
        recorder: StreamingStageRecorder? = nil
    ) {
        state = DemandTrackedBodyState(
            chunks: chunks,
            gatedNextCall: gatedNextCall,
            termination: termination,
            recorder: recorder
        )
    }

    var nextCallCount: Int {
        get async { await state.nextCallCount }
    }

    func waitForNextCallCount(_ count: Int) async {
        await state.waitForNextCallCount(count)
    }

    func releaseGate() async {
        await state.releaseGate()
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(state: state)
    }
}

func gatewayChatStreamingResponse(
    _ body: DemandTrackedBodySequence,
    contentType: String = "text/event-stream"
) -> HTTPClientResponse {
    HTTPClientResponse(
        status: .ok,
        headers: ["content-type": contentType],
        body: .stream(body)
    )
}

func gatewayLiveChatContext(
    fixture: GatewayFixture,
    streaming: Bool = true,
    includeTools: Bool = true
) throws -> TransparentResponsesContext {
    let mapping = try #require(
        fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
    )
    let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
    let target = try #require(fixture.snapshot.resolveCodex(model: slug))
    var root: [String: Any] = [
        "model": slug,
        "input": "Keep this live.",
        "stream": streaming,
    ]
    if includeTools {
        root["tools"] = [
            [
                "type": "function",
                "name": "read_file",
                "parameters": ["type": "object"],
            ]
        ]
    }
    let body = try JSONSerialization.data(
        withJSONObject: root,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return TransparentResponsesContext(
        body: body,
        model: slug,
        target: target,
        credential: "selected-secret",
        incomingHeaders: [:],
        eventID: UUID(),
        streaming: streaming
    )
}

func gatewayChatCompletionChunks() throws -> [Data] {
    let first = gatewayChatChunk(choices: [
        gatewayChatChoice(delta: ["role": "assistant", "content": "FIRST"])
    ])
    let tail =
        try [
            gatewayChatChunk(choices: [
                gatewayChatChoice(delta: ["content": " SECOND"])
            ]),
            gatewayChatChunk(choices: [
                gatewayChatChoice(delta: [:], finishReason: "stop")
            ]),
            gatewayChatChunk(
                choices: [],
                usage: [
                    "prompt_tokens": 4,
                    "completion_tokens": 2,
                    "total_tokens": 6,
                ]
            ),
        ].map(gatewayChatSSE).joined() + Data("data: [DONE]\n\n".utf8)
    return [try gatewayChatSSE(first), tail]
}

private func gatewayChatChunk(
    choices: [[String: Any]],
    usage: [String: Any]? = nil
) -> [String: Any] {
    var chunk: [String: Any] = [
        "id": "chatcmpl_gateway_live",
        "object": "chat.completion.chunk",
        "created": 123,
        "model": "glm-5.2",
        "choices": choices,
    ]
    if let usage {
        chunk["usage"] = usage
    }
    return chunk
}

private func gatewayChatChoice(
    delta: [String: Any],
    finishReason: String? = nil
) -> [String: Any] {
    [
        "index": 0,
        "delta": delta,
        "finish_reason": finishReason ?? NSNull(),
    ]
}

private func gatewayChatSSE(_ object: [String: Any]) throws -> Data {
    var data = Data("data: ".utf8)
    data.append(
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    )
    data.append(Data("\n\n".utf8))
    return data
}
