import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic provider stream fragment buffering")
struct AnthropicStreamingFragmentBufferTests {
    @Test("Fragment buffer joins 2,048 Unicode fragments in order")
    func fragmentBufferJoinsUnicodeInOrder() {
        let fragments = (0..<2_048).map { "é\($0)👩🏽‍💻|" }
        var buffer = AnthropicStreamFragmentBuffer()

        for fragment in fragments {
            buffer.append(fragment)
        }

        #expect(!buffer.isEmpty)
        #expect(buffer.joined() == fragments.joined())
    }

    @Test("Empty fragments remain an empty accumulated value")
    func emptyFragmentsRemainEmpty() {
        var buffer = AnthropicStreamFragmentBuffer()

        for _ in 0..<2_048 {
            buffer.append("")
        }

        #expect(buffer.isEmpty)
        #expect(buffer.joined().isEmpty)
    }

    @Test("Highly fragmented blocks preserve content, citations, and event order")
    func highlyFragmentedBlocksPreserveOrder() throws {
        let fixture = HighlyFragmentedTurnFixture(fragmentCount: 2_048)
        var recorder = AnthropicTurnRecorder(maximumTurnBytes: 8 * 1_024 * 1_024)

        try recorder.consume(fragmentedMessageStart())
        try streamTextBlock(fixture, into: &recorder)
        try streamThinkingBlock(fixture, into: &recorder)
        try streamToolInput(fixture, into: &recorder)
        try streamTerminal(into: &recorder)

        let turn = try recorder.finish()
        try assertFragmentedContent(turn, fixture: fixture)
        assertFragmentedEventOrder(recorder, fragmentCount: fixture.fragmentCount)
    }
}

private struct HighlyFragmentedTurnFixture {
    let fragmentCount: Int
    let textFragments: [String]
    let thinkingFragments: [String]
    let queryFragments: [String]
    let expectedQuery: String
    let streamedCitations: [[String: Any]]
    let initialCitation: [String: Any]

    init(fragmentCount: Int) {
        self.fragmentCount = fragmentCount
        textFragments = (0..<fragmentCount).map { "t\($0)-é👩🏽‍💻|" }
        thinkingFragments = (0..<fragmentCount).map { "θ\($0)-🧠|" }
        queryFragments =
            [#"{"query":""#]
            + Array(repeating: "検", count: fragmentCount - 2)
            + [#""}"#]
        expectedQuery = String(repeating: "検", count: fragmentCount - 2)
        streamedCitations = [
            [
                "type": "web_search_result_location",
                "url": "https://one.example/",
                "title": "One",
            ],
            [
                "type": "web_search_result_location",
                "url": "https://two.example/",
                "title": "Two",
            ],
        ]
        initialCitation = [
            "type": "web_search_result_location",
            "url": "https://initial.example/",
            "title": "Initial",
        ]
    }
}

private struct AnthropicTurnRecorder {
    private var accumulator: AnthropicStreamingTurnAccumulator
    private(set) var publishedIndexes: [Int] = []
    private(set) var publishedDeltaTypes: [String] = []

    init(maximumTurnBytes: Int) {
        accumulator = AnthropicStreamingTurnAccumulator(
            maximumTurnBytes: maximumTurnBytes
        )
    }

    mutating func consume(_ frame: ServerSentEventFrame) throws {
        guard let event = try accumulator.consume(frame) else { return }
        switch event {
        case .contentStart(let index, _), .contentStop(let index):
            publishedIndexes.append(index)
        // Swift Format expands these bindings in the form SwiftLint rejects.
        // swiftlint:disable:next pattern_matching_keywords
        case .contentDelta(let index, let deltaJSON):
            publishedIndexes.append(index)
            let delta = try liveJSONObject(deltaJSON)
            publishedDeltaTypes.append(try #require(delta["type"] as? String))
        default:
            break
        }
    }

    mutating func finish() throws -> AnthropicModelTurn {
        try accumulator.finish()
    }
}

private func fragmentedMessageStart() throws -> ServerSentEventFrame {
    try providerFrame(
        "message_start",
        [
            "type": "message_start",
            "message": providerMessage(id: "msg_fragmented", inputTokens: 11),
        ]
    )
}

private func streamTextBlock(
    _ fixture: HighlyFragmentedTurnFixture,
    into recorder: inout AnthropicTurnRecorder
) throws {
    try recorder.consume(
        providerBlockStart(
            index: 0,
            block: [
                "type": "text",
                "text": "initial-text|",
                "citations": [fixture.initialCitation],
            ]
        )
    )
    for (offset, fragment) in fixture.textFragments.enumerated() {
        try recorder.consume(
            providerBlockDelta(
                index: 0,
                delta: ["type": "text_delta", "text": fragment]
            )
        )
        if offset < fixture.streamedCitations.count {
            try recorder.consume(
                providerBlockDelta(
                    index: 0,
                    delta: [
                        "type": "citations_delta",
                        "citation": fixture.streamedCitations[offset],
                    ]
                )
            )
        }
    }
    try recorder.consume(providerBlockStop(index: 0))
}

private func streamThinkingBlock(
    _ fixture: HighlyFragmentedTurnFixture,
    into recorder: inout AnthropicTurnRecorder
) throws {
    try recorder.consume(
        providerBlockStart(
            index: 1,
            block: [
                "type": "thinking",
                "thinking": "initial-thinking|",
                "signature": "",
            ]
        )
    )
    for fragment in fixture.thinkingFragments {
        try recorder.consume(
            providerBlockDelta(
                index: 1,
                delta: ["type": "thinking_delta", "thinking": fragment]
            )
        )
    }
    try recorder.consume(
        providerBlockDelta(
            index: 1,
            delta: ["type": "signature_delta", "signature": "signed"]
        )
    )
    try recorder.consume(providerBlockStop(index: 1))
}

private func streamToolInput(
    _ fixture: HighlyFragmentedTurnFixture,
    into recorder: inout AnthropicTurnRecorder
) throws {
    try recorder.consume(
        providerBlockStart(
            index: 2,
            block: [
                "type": "tool_use",
                "id": "toolu_fragmented",
                "name": "web_search",
                "input": [:],
            ]
        )
    )
    for fragment in fixture.queryFragments {
        try recorder.consume(
            providerBlockDelta(
                index: 2,
                delta: [
                    "type": "input_json_delta",
                    "partial_json": fragment,
                ]
            )
        )
    }
    try recorder.consume(providerBlockStop(index: 2))
}

private func streamTerminal(into recorder: inout AnthropicTurnRecorder) throws {
    try recorder.consume(
        providerFrame(
            "message_delta",
            [
                "type": "message_delta",
                "delta": ["stop_reason": "tool_use", "stop_sequence": NSNull()],
                "usage": ["output_tokens": 17],
            ]
        )
    )
    try recorder.consume(providerFrame("message_stop", ["type": "message_stop"]))
}

private func providerBlockStart(
    index: Int,
    block: [String: Any]
) throws -> ServerSentEventFrame {
    try providerFrame(
        "content_block_start",
        [
            "type": "content_block_start",
            "index": index,
            "content_block": block,
        ]
    )
}

private func providerBlockDelta(
    index: Int,
    delta: [String: Any]
) throws -> ServerSentEventFrame {
    try providerFrame(
        "content_block_delta",
        [
            "type": "content_block_delta",
            "index": index,
            "delta": delta,
        ]
    )
}

private func providerBlockStop(index: Int) throws -> ServerSentEventFrame {
    try providerFrame(
        "content_block_stop",
        ["type": "content_block_stop", "index": index]
    )
}

private func assertFragmentedContent(
    _ turn: AnthropicModelTurn,
    fixture: HighlyFragmentedTurnFixture
) throws {
    let content = try jsonArray(turn.contentJSON)
    #expect(content.count == 3)

    let text = try jsonDictionary(content[0])
    #expect(text["text"] as? String == "initial-text|" + fixture.textFragments.joined())
    let citations = try #require(text["citations"] as? [[String: Any]])
    #expect(
        citations.compactMap { $0["url"] as? String }
            == [
                "https://initial.example/",
                "https://one.example/",
                "https://two.example/",
            ]
    )

    let thinking = try jsonDictionary(content[1])
    #expect(
        thinking["thinking"] as? String
            == "initial-thinking|" + fixture.thinkingFragments.joined()
    )
    #expect(thinking["signature"] as? String == "signed")

    let tool = try jsonDictionary(content[2])
    #expect((tool["input"] as? [String: String]) == ["query": fixture.expectedQuery])
}

private func assertFragmentedEventOrder(
    _ recorder: AnthropicTurnRecorder,
    fragmentCount: Int
) {
    #expect(recorder.publishedIndexes.first == 0)
    #expect(recorder.publishedIndexes.last == 2)

    let textDeltaTypes = recorder.publishedDeltaTypes.prefix(fragmentCount + 2)
    #expect(
        Array(textDeltaTypes.prefix(5))
            == [
                "text_delta",
                "citations_delta",
                "text_delta",
                "citations_delta",
                "text_delta",
            ]
    )
    #expect(textDeltaTypes.dropFirst(5).allSatisfy { $0 == "text_delta" })

    let nonTextDeltaTypes = recorder.publishedDeltaTypes.dropFirst(fragmentCount + 2)
    #expect(
        nonTextDeltaTypes.prefix(fragmentCount)
            .allSatisfy { $0 == "thinking_delta" }
    )
    #expect(nonTextDeltaTypes.dropFirst(fragmentCount).first == "signature_delta")
    #expect(
        nonTextDeltaTypes.dropFirst(fragmentCount + 1)
            .allSatisfy { $0 == "input_json_delta" }
    )
    #expect(recorder.publishedDeltaTypes.count == fragmentCount * 3 + 3)
}
