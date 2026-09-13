import Foundation
import LittleSwitchTransport
import LittleSwitchWire

struct AnthropicStreamFragmentBuffer: Sendable {
    private var fragments: [String] = []
    init() {}
    var isEmpty: Bool { fragments.isEmpty }
    mutating func append(_ fragment: String) {
        guard !fragment.isEmpty else { return }
        fragments.append(fragment)
    }
    func joined() -> String { fragments.joined() }
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
    private enum Phase: Sendable { case awaitingStart, content, messageDelta, stopped, finished }

    private struct ContentBlock: Sendable {
        var value: AnthropicIncomingContentBlock
        var textDelta = AnthropicStreamFragmentBuffer()
        var thinkingDelta = AnthropicStreamFragmentBuffer()
        var signatureDelta: String?
        var inputDelta = AnthropicStreamFragmentBuffer()
        var completedInput: JSONValue?
        var citations: [AnthropicCitationIdentity] = []
        var stopped = false
    }

    private let maximumTurnBytes: Int
    private let privateToolName: String?
    private var consumedBytes = 0
    private var phase = Phase.awaitingStart
    private var message: AnthropicMessage?
    private var blocks: [ContentBlock] = []
    private var terminalDelta = AnthropicTerminalDeltaState()
    private var terminalUsage = AnthropicTerminalUsageState()

    package init(maximumTurnBytes: Int, privateToolName: String? = "web_search") {
        self.maximumTurnBytes = max(0, maximumTurnBytes)
        self.privateToolName = privateToolName
    }

    @discardableResult
    package mutating func consume(_ frame: ServerSentEventFrame) throws -> AnthropicProviderStreamEvent? {
        guard !frame.terminal else { throw AnthropicWebSearch.Error.invalidMessage }
        let event: AnthropicStreamEvent
        do { event = try WireCodec.decode(AnthropicStreamEvent.self, from: frame.data).value } catch {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let type = anthropicStreamEventType(event)
        guard frame.event == type else { throw AnthropicWebSearch.Error.invalidMessage }
        if case .unknown = event {
            if type == "ping" { return .ping }
            if type == "error" { throw AnthropicWebSearch.Error.invalidMessage }
            return nil
        }
        try charge(frame.data.count)
        switch event {
        case .messageStart(let value): return try consumeMessageStart(value)
        case .contentBlockStart(let value): return try consumeContentStart(value)
        case .contentBlockDelta(let value): return try consumeContentDelta(value)
        case .contentBlockStop(let value): return try consumeContentStop(value)
        case .messageDelta(let value): return try consumeMessageDelta(value)
        case .messageStop:
            guard phase == .messageDelta else { throw AnthropicWebSearch.Error.invalidMessage }
            phase = .stopped
            return .messageStop
        case .unknown: return nil
        }
    }

    package mutating func finish() throws -> AnthropicModelTurn {
        guard phase == .stopped, var message, blocks.allSatisfy(\.stopped) else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        message.content = try blocks.map { try completeBlock($0).wireJSON() }
        terminalDelta.apply(to: &message)
        message.usage = try terminalUsage.wireJSON()
        let turn = try AnthropicWebSearch.parseModelTurn(
            WireCodec.encode(message), privateToolName: privateToolName
        )
        phase = .finished
        return turn
    }
}

extension AnthropicStreamingTurnAccumulator {
    private mutating func consumeMessageStart(
        _ event: AnthropicMessageStartEvent
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .awaitingStart, let raw = event.message else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let message = try anthropicDecode(AnthropicMessage.self, from: raw)
        guard !message.id.isEmpty, message.content.isEmpty, let usage = message.usage else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let usageState = try AnthropicTerminalUsageState(usage)
        let data = try WireCodec.encode(message)
        self.message = message
        terminalUsage = usageState
        phase = .content
        return .messageStart(messageJSON: data)
    }

    private mutating func consumeContentStart(
        _ event: AnthropicContentBlockStartEvent
    ) throws -> AnthropicProviderStreamEvent {
        let index = try anthropicTokenCount(event.index)
        guard phase == .content, index == blocks.count, let raw = event.contentBlock else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let block = try anthropicDecode(AnthropicIncomingContentBlock.self, from: raw)
        try validateBlockStart(block)
        let data = try WireCodec.encode(block)
        blocks.append(ContentBlock(value: block))
        return .contentStart(index: index, blockJSON: data)
    }

    private mutating func consumeContentDelta(
        _ event: AnthropicContentBlockDeltaEvent
    ) throws -> AnthropicProviderStreamEvent {
        let index = try anthropicTokenCount(event.index)
        guard phase == .content, blocks.indices.contains(index), !blocks[index].stopped, let raw = event.delta else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let delta = try anthropicDecode(AnthropicContentDelta.self, from: raw)
        switch delta {
        case .textDelta(let delta):
            guard case .text = blocks[index].value else { throw AnthropicWebSearch.Error.invalidMessage }
            blocks[index].textDelta.append(delta.text)
        case .inputJsonDelta(let delta):
            switch blocks[index].value {
            case .toolUse, .serverToolUse: break
            default: throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].inputDelta.append(delta.partialJson)
        case .thinkingDelta(let delta):
            guard case .thinking = blocks[index].value else { throw AnthropicWebSearch.Error.invalidMessage }
            blocks[index].thinkingDelta.append(delta.thinking)
        case .signatureDelta(let delta):
            guard case .thinking = blocks[index].value else { throw AnthropicWebSearch.Error.invalidMessage }
            blocks[index].signatureDelta = delta.signature
        case .citationsDelta(let delta):
            guard case .text = blocks[index].value, case .value(let raw) = delta.citation else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            blocks[index].citations.append(try anthropicDecode(AnthropicCitationIdentity.self, from: raw))
        case .unknown(let type, _):
            guard !type.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
        }
        return .contentDelta(index: index, deltaJSON: try WireCodec.encode(delta))
    }

    private mutating func consumeContentStop(
        _ event: AnthropicContentBlockStopEvent
    ) throws -> AnthropicProviderStreamEvent {
        let index = try anthropicTokenCount(event.index)
        guard phase == .content, blocks.indices.contains(index), !blocks[index].stopped else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        switch blocks[index].value {
        case .toolUse, .serverToolUse:
            let input: JSONValue
            if blocks[index].inputDelta.isEmpty {
                input = [:]
            } else {
                do { input = try JSONValue.parse(blocks[index].inputDelta.joined()) } catch {
                    throw AnthropicWebSearch.Error.invalidMessage
                }
                guard input.object != nil else { throw AnthropicWebSearch.Error.invalidMessage }
            }
            blocks[index].completedInput = input
        default: break
        }
        blocks[index].stopped = true
        return .contentStop(index: index)
    }

    private mutating func consumeMessageDelta(
        _ event: AnthropicMessageDeltaEvent
    ) throws -> AnthropicProviderStreamEvent {
        guard phase == .content || phase == .messageDelta, blocks.allSatisfy(\.stopped), let usage = event.usage else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var updatedUsage = terminalUsage
        var updatedDelta = terminalDelta
        updatedDelta.apply(event.delta)
        try updatedUsage.apply(usage)
        let deltaData = try WireCodec.encode(event.delta)
        let usageData = try usage.serializedData()
        terminalDelta = updatedDelta
        terminalUsage = updatedUsage
        phase = .messageDelta
        return .messageDelta(deltaJSON: deltaData, usageJSON: usageData)
    }

    private func completeBlock(_ state: ContentBlock) throws -> AnthropicIncomingContentBlock {
        switch state.value {
        case .text(var block):
            block.text += state.textDelta.joined()
            if !state.citations.isEmpty {
                block.citations = .value(
                    (block.citations.value ?? []) + (try state.citations.map { try $0.wireJSON() }))
            }
            return .text(block)
        case .thinking(var block):
            block.thinking += state.thinkingDelta.joined()
            if let signature = state.signatureDelta { block.signature = signature }
            return .thinking(block)
        case .toolUse(var block):
            if let input = state.completedInput { block.input = input }
            return .toolUse(block)
        case .serverToolUse(var block):
            if let input = state.completedInput { block.input = input }
            return .serverToolUse(block)
        default: return state.value
        }
    }

    private mutating func charge(_ byteCount: Int) throws {
        guard consumedBytes <= maximumTurnBytes, byteCount <= maximumTurnBytes - consumedBytes else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        consumedBytes += byteCount
    }
}

private func anthropicStreamEventType(_ event: AnthropicStreamEvent) -> String {
    switch event {
    case .messageStart(let value): value.type.rawValue
    case .messageDelta(let value): value.type.rawValue
    case .messageStop(let value): value.type.rawValue
    case .contentBlockStart(let value): value.type.rawValue
    case .contentBlockDelta(let value): value.type.rawValue
    case .contentBlockStop(let value): value.type.rawValue
    case .unknown(let discriminator, _): discriminator
    }
}

private func validateBlockStart(_ block: AnthropicIncomingContentBlock) throws {
    switch block {
    case .toolUse(let block):
        guard !block.id.isEmpty, !block.name.isEmpty, block.input?.object?.isEmpty == true else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
    case .serverToolUse(let block):
        guard !block.id.isEmpty, !block.name.rawValue.isEmpty, block.input?.object?.isEmpty == true else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
    case .unknown(let type, _):
        guard !type.isEmpty else { throw AnthropicWebSearch.Error.invalidMessage }
    default: break
    }
}
