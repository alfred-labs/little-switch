import Foundation
import LittleSwitchWire

func publicContentStartFrames(
    _ content: AnthropicContentBlock, index: Int, includeToolInput: Bool = false
) throws -> [Data] {
    let start: AnthropicContentBlock
    var deltas: [AnthropicContentDelta] = []
    switch content {
    case .text(var block):
        if !block.text.isEmpty || includeToolInput {
            deltas.append(.textDelta(AnthropicTextDelta(text: block.text, type: .textDelta)))
        }
        block.text = ""
        start = .text(block)
    case .thinking(var block):
        if !block.thinking.isEmpty {
            deltas.append(.thinkingDelta(AnthropicThinkingDelta(thinking: block.thinking, type: .thinkingDelta)))
        }
        if let signature = block.signature, !signature.isEmpty {
            deltas.append(.signatureDelta(AnthropicSignatureDelta(signature: signature, type: .signatureDelta)))
        }
        block.thinking = ""
        block.signature = block.signature.map { _ in "" }
        start = .thinking(block)
    case .toolUse(var block) where includeToolInput:
        deltas.append(try inputDelta(block.input))
        block.input = [:]
        start = .toolUse(block)
    case .serverToolUse(var block) where includeToolInput:
        deltas.append(try inputDelta(block.input))
        block.input = [:]
        start = .serverToolUse(block)
    default:
        start = content
    }
    var frames = [
        try publicStreamFrame(
            name: AnthropicContentBlockStartEventType.contentBlockStart.rawValue,
            payload: AnthropicContentBlockStartEvent(
                contentBlock: start.wireJSON(), index: JSONNumber(index), type: .contentBlockStart
            ).wireJSON()
        )
    ]
    for delta in deltas {
        frames.append(try contentDeltaFrame(index: index, deltaJSON: WireCodec.encode(delta)))
    }
    return frames
}

private func inputDelta(_ value: JSONValue?) throws -> AnthropicContentDelta {
    guard let value, value.object != nil else { throw AnthropicWebSearch.Error.invalidMessage }
    let data = try value.serializedData()
    // The exact JSON codec emits UTF-8.
    // swiftlint:disable:next optional_data_string_conversion
    let text = String(decoding: data, as: UTF8.self)
    return .inputJsonDelta(AnthropicInputJSONDelta(partialJson: text, type: .inputJsonDelta))
}

extension AnthropicWebSearch {
    static func appendStreamingBlock(_ block: [String: JSONValue], index: Int, to stream: inout Data) throws {
        let value = try anthropicDecode(AnthropicContentBlock.self, from: anthropicJSON(block))
        for frame in try publicContentStartFrames(value, index: index, includeToolInput: true) { stream.append(frame) }
        stream.append(try contentStopFrame(index: index))
    }
}
