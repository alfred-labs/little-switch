import Foundation
import LittleSwitchTransport

struct AnthropicStreamFragmentBuffer: Sendable {
    private var fragments: [String] = []

    init() {}

    var isEmpty: Bool {
        fragments.isEmpty
    }

    mutating func append(_ fragment: String) {
        guard !fragment.isEmpty else { return }
        fragments.append(fragment)
    }

    func joined() -> String {
        fragments.joined()
    }
}

package enum AnthropicProviderStreamEvent: Equatable, Sendable {
    case messageStart(messageJSON: Data)
    case contentStart(index: Int, blockJSON: Data)
    case contentDelta(index: Int, deltaJSON: Data)
    case contentStop(index: Int)
    case messageDelta(deltaJSON: Data, usageJSON: Data)
    case messageStop
    case ping
}

package struct AnthropicStreamingTurnAccumulator: Sendable {
    private enum Phase: Sendable {
        case awaitingStart
        case content
        case messageDelta
        case stopped
        case finished
    }

    private struct ContentBlock: Sendable {
        let type: String
        let startJSON: Data
        var textDelta = AnthropicStreamFragmentBuffer()
        var thinkingDelta = AnthropicStreamFragmentBuffer()
        var signatureDelta: String?
        var inputDelta = AnthropicStreamFragmentBuffer()
        var completedInputJSON: Data?
        var citationJSON: [Data] = []
        var stopped = false
    }

    private let maximumTurnBytes: Int
    private let privateToolName: String?
    private var consumedBytes = 0
    private var phase = Phase.awaitingStart
    private var messageJSON: Data?
    private var blocks: [ContentBlock] = []
    private var terminalDelta = AnthropicTerminalDeltaState()
    private var terminalUsage = AnthropicTerminalUsageState()

    /// Events whose per-frame bytes are charged against the turn budget;
    /// built once instead of per frame in the consume loop.
    private static let statefulEvents: Set<String> = [
        "message_start",
        "content_block_start",
        "content_block_delta",
        "content_block_stop",
        "message_delta",
        "message_stop",
    ]

    package init(maximumTurnBytes: Int, privateToolName: String? = "web_search") {
        self.maximumTurnBytes = max(0, maximumTurnBytes)
        self.privateToolName = privateToolName
    }

    @discardableResult
    package mutating func consume(
        _ frame: ServerSentEventFrame
    ) throws -> AnthropicProviderStreamEvent? {
        guard !frame.terminal else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let payload = try anthropicStreamObject(frame.data)
        guard let eventName = frame.event,
            let payloadType = payload["type"] as? String,
            payloadType == eventName
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        if Self.statefulEvents.contains(eventName) {
            try charge(frame.data.count)
        }

        switch eventName {
        case "message_start":
            return try consumeMessageStart(payload)
        case "content_block_start":
            return try consumeContentStart(payload)
        case "content_block_delta":
            return try consumeContentDelta(payload)
        case "content_block_stop":
            return try consumeContentStop(payload)
        case "message_delta":
            return try consumeMessageDelta(payload)
        case "message_stop":
            return try consumeMessageStop()
        case "ping":
            return .ping
        case "error":
            throw AnthropicWebSearch.Error.invalidMessage
        default:
            return nil
        }
    }

    package mutating func finish() throws -> AnthropicModelTurn {
        guard phase == .stopped,
            let messageJSON,
            blocks.allSatisfy(\.stopped)
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        var message = try anthropicStreamObject(messageJSON)
        message["content"] = try blocks.map(completeBlock)
        terminalDelta.apply(to: &message)
        message["usage"] = terminalUsage.jsonObject

        let completeMessage = try anthropicStreamData(message)
        let turn = try AnthropicWebSearch.parseModelTurn(completeMessage, privateToolName: privateToolName)
        phase = .finished
        return turn
    }
}

extension AnthropicStreamingTurnAccumulator {
    private mutating func consumeMessageStart(
        _ payload: [String: Any]
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .awaitingStart,
            let message = payload["message"] as? [String: Any],
            let id = message["id"] as? String,
            !id.isEmpty,
            let content = message["content"] as? [Any],
            content.isEmpty,
            let usage = message["usage"] as? [String: Any]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let usageState = try AnthropicTerminalUsageState(usage)
        let data = try anthropicStreamData(message)
        messageJSON = data
        terminalUsage = usageState
        phase = .content
        return .messageStart(messageJSON: data)
    }

    private mutating func consumeContentStart(
        _ payload: [String: Any]
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .content,
            let index = nonnegativeIndex(payload["index"]),
            index == blocks.count,
            let block = payload["content_block"] as? [String: Any],
            let type = block["type"] as? String,
            !type.isEmpty
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        try validateBlockStart(block, type: type)
        let data = try anthropicStreamData(block)
        blocks.append(ContentBlock(type: type, startJSON: data))
        return .contentStart(index: index, blockJSON: data)
    }

    private mutating func consumeContentDelta(
        _ payload: [String: Any]
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .content,
            let index = nonnegativeIndex(payload["index"]),
            blocks.indices.contains(index),
            !blocks[index].stopped,
            let delta = payload["delta"] as? [String: Any],
            let type = delta["type"] as? String,
            !type.isEmpty
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        switch type {
        case "text_delta":
            guard blocks[index].type == "text",
                let text = delta["text"] as? String
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].textDelta.append(text)
        case "input_json_delta":
            guard ["tool_use", "server_tool_use"].contains(blocks[index].type),
                let partialJSON = delta["partial_json"] as? String
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].inputDelta.append(partialJSON)
        case "thinking_delta":
            guard blocks[index].type == "thinking",
                let thinking = delta["thinking"] as? String
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].thinkingDelta.append(thinking)
        case "signature_delta":
            guard blocks[index].type == "thinking",
                let signature = delta["signature"] as? String
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].signatureDelta = signature
        case "citations_delta":
            guard blocks[index].type == "text",
                let citation = delta["citation"] as? [String: Any],
                citation["type"] is String
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].citationJSON.append(try anthropicStreamData(citation))
        default:
            break
        }

        let data = try anthropicStreamData(delta)
        return .contentDelta(index: index, deltaJSON: data)
    }

    private mutating func consumeContentStop(
        _ payload: [String: Any]
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .content,
            let index = nonnegativeIndex(payload["index"]),
            blocks.indices.contains(index),
            !blocks[index].stopped
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        if ["tool_use", "server_tool_use"].contains(blocks[index].type) {
            let input: [String: Any]
            if blocks[index].inputDelta.isEmpty {
                input = [:]
            } else {
                input = try anthropicStreamObject(
                    Data(blocks[index].inputDelta.joined().utf8)
                )
            }
            blocks[index].completedInputJSON = try anthropicStreamData(input)
        }
        blocks[index].stopped = true
        return .contentStop(index: index)
    }

    private mutating func consumeMessageDelta(
        _ payload: [String: Any]
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .content || phase == .messageDelta,
            blocks.allSatisfy(\.stopped),
            let delta = payload["delta"] as? [String: Any],
            let usage = payload["usage"] as? [String: Any]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var updatedUsage = terminalUsage
        var updatedDelta = terminalDelta
        try updatedDelta.apply(delta)
        try updatedUsage.apply(usage)
        let deltaData = try anthropicStreamData(delta)
        let usageData = try anthropicStreamData(usage)
        terminalDelta = updatedDelta
        terminalUsage = updatedUsage
        phase = .messageDelta
        return .messageDelta(deltaJSON: deltaData, usageJSON: usageData)
    }

    private mutating func consumeMessageStop() throws -> AnthropicProviderStreamEvent {
        guard phase == .messageDelta else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        phase = .stopped
        return .messageStop
    }

    private func completeBlock(_ state: ContentBlock) throws -> [String: Any] {
        var block = try anthropicStreamObject(state.startJSON)
        switch state.type {
        case "text":
            if let initialText = block["text"] as? String {
                block["text"] = initialText + state.textDelta.joined()
            }
            if !state.citationJSON.isEmpty {
                var citations = block["citations"] as? [Any] ?? []
                citations += try state.citationJSON.map { try anthropicStreamObject($0) }
                block["citations"] = citations
            }
        case "thinking":
            if let initialThinking = block["thinking"] as? String {
                block["thinking"] = initialThinking + state.thinkingDelta.joined()
            }
            if let signatureDelta = state.signatureDelta {
                block["signature"] = signatureDelta
            }
        case "tool_use", "server_tool_use":
            if let completedInputJSON = state.completedInputJSON {
                block["input"] = try anthropicStreamObject(completedInputJSON)
            }
        default:
            break
        }
        return block
    }

    private mutating func charge(_ byteCount: Int) throws {
        guard consumedBytes <= maximumTurnBytes,
            byteCount <= maximumTurnBytes - consumedBytes
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        consumedBytes += byteCount
    }
}

private func validateBlockStart(
    _ block: [String: Any],
    type: String
) throws {
    switch type {
    case "text":
        guard block["text"] is String else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        if let citations = block["citations"] {
            guard citations is [Any] || citations is NSNull else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
        }
    case "thinking":
        guard block["thinking"] is String else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        if let signature = block["signature"], !(signature is String) {
            throw AnthropicWebSearch.Error.invalidMessage
        }
    case "tool_use", "server_tool_use":
        guard let id = block["id"] as? String,
            !id.isEmpty,
            let name = block["name"] as? String,
            !name.isEmpty,
            let input = block["input"] as? [String: Any],
            input.isEmpty
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
    default:
        break
    }
}

private func nonnegativeIndex(_ value: Any?) -> Int? {
    guard let index = value as? Int, index >= 0 else {
        return nil
    }
    return index
}

private func anthropicStreamObject(_ data: Data) throws -> [String: Any] {
    do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return object
    } catch let error as AnthropicWebSearch.Error {
        throw error
    } catch {
        throw AnthropicWebSearch.Error.invalidMessage
    }
}

private func anthropicStreamData(_ value: Any) throws -> Data {
    try AnthropicWebSearch.serialize(
        value,
        options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    ) { value, options in
        try JSONSerialization.data(withJSONObject: value, options: options)
    }
}
