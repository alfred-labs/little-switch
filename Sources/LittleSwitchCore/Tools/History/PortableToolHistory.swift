import Foundation
import LittleSwitchWire

private struct HistoricalServerToolCall {
    let position: Int
    let name: String
    let input: String
}

/// Imports completed server-side work as conversation data. No converted item
/// asks the client or the next provider to execute the historical tool again.
package enum PortableToolHistory {
    package enum Error: Swift.Error, Equatable {
        case invalidServerHistory
        case nonportableResult
    }

    private static let serverResultTypes: Set<String> = [
        "web_search_tool_result", "web_fetch_tool_result", "code_execution_tool_result",
        "bash_code_execution_tool_result", "text_editor_code_execution_tool_result",
        "tool_search_tool_result",
    ]

    package static func anthropic(_ root: [String: JSONValue]) throws -> [String: JSONValue] {
        guard let messages = root[AnthropicCountTokensProjection.Key.messages.rawValue]?.anthropicObjects else {
            return root
        }
        let blocks = messages.flatMap { message -> [[String: JSONValue]] in
            (message[AnthropicMessageParam.Key.content.rawValue]?.array ?? []).compactMap(\.anthropicObject)
        }
        let calls = try serverCalls(in: blocks)
        guard !calls.isEmpty || blocks.contains(where: isServerResult) else {
            return root
        }
        try validateResults(in: blocks, calls: calls)
        var result = root
        result[AnthropicCountTokensProjection.Key.messages.rawValue] = .array(
            try messages.map { message in
                guard let content = message[AnthropicMessageParam.Key.content.rawValue]?.array else {
                    return anthropicJSON(message)
                }
                var rewritten = message
                rewritten[AnthropicMessageParam.Key.content.rawValue] = .array(
                    try content.map { value -> JSONValue in
                        guard let block = value.anthropicObject else {
                            throw Error.invalidServerHistory
                        }
                        return try anthropicJSON(projectedBlock(block, calls: calls))
                    })
                return anthropicJSON(rewritten)
            })
        return result
    }

    private static func serverCalls(
        in blocks: [[String: JSONValue]]
    ) throws -> [String: HistoricalServerToolCall] {
        var calls: [String: HistoricalServerToolCall] = [:]
        let clientBlocks = blocks.filter {
            $0[AnthropicToolUseParam.Key.type.rawValue]?.string == AnthropicToolUseParamType.toolUse.rawValue
        }
        let clientIDs = Set(clientBlocks.compactMap { $0[AnthropicToolUseParam.Key.id.rawValue]?.string })
        for (position, block) in blocks.enumerated() {
            let type = block[AnthropicToolUseParam.Key.type.rawValue]?.string
            guard type == AnthropicServerToolUseParamType.serverToolUse.rawValue else { continue }
            guard let id = nonempty(block[AnthropicServerToolUseParam.Key.id.rawValue]),
                let name = nonempty(block[AnthropicServerToolUseParam.Key.name.rawValue]),
                let input = block[AnthropicServerToolUseParam.Key.input.rawValue]?.anthropicObject,
                calls[id] == nil, !clientIDs.contains(id)
            else {
                throw Error.invalidServerHistory
            }
            calls[id] = HistoricalServerToolCall(
                position: position, name: name, input: try jsonText(input)
            )
        }
        return calls
    }

    private static func validateResults(
        in blocks: [[String: JSONValue]],
        calls: [String: HistoricalServerToolCall]
    ) throws {
        var completed: Set<String> = []
        for (position, block) in blocks.enumerated() {
            let id = block[AnthropicToolResultParam.Key.toolUseId.rawValue]?.string
            let serverResult = isServerResult(block)
            let clientResult =
                block[AnthropicToolUseParam.Key.type.rawValue]?.string
                == AnthropicToolResultParamType.toolResult.rawValue
            guard serverResult || (clientResult && id.map { calls[$0] != nil } == true) else {
                continue
            }
            guard let id, let call = calls[id], call.position < position,
                completed.insert(id).inserted
            else {
                throw Error.invalidServerHistory
            }
        }
        guard completed.count == calls.count else {
            throw Error.invalidServerHistory
        }
    }

    private static func projectedBlock(
        _ block: [String: JSONValue],
        calls: [String: HistoricalServerToolCall]
    ) throws -> [String: JSONValue] {
        let type = block[AnthropicToolUseParam.Key.type.rawValue]?.string
        if type == AnthropicServerToolUseParamType.serverToolUse.rawValue {
            if let id = block[AnthropicServerToolUseParam.Key.id.rawValue]?.string, let call = calls[id] {
                return try text("[Previous server tool: \(call.name)]\nInput: \(call.input)")
            }
        }
        guard let id = block[AnthropicToolResultParam.Key.toolUseId.rawValue]?.string, let call = calls[id],
            isServerResult(block) || type == AnthropicToolResultParamType.toolResult.rawValue
        else {
            return block
        }
        if type == AnthropicWebSearchToolResultBlockType.webSearchToolResult.rawValue {
            return try text(try PortableWebSearchHistory.anthropicResultText(block))
        }
        if let error = block[AnthropicToolResultParam.Key.isError.rawValue], error.boolean == nil {
            throw Error.invalidServerHistory
        }
        let state = block[AnthropicToolResultParam.Key.isError.rawValue]?.boolean == true ? "error" : "result"
        let content = try readableContent(block[AnthropicToolResultParam.Key.content.rawValue])
        return try text("[Previous server tool \(state): \(call.name)]\n\(content)")
    }

    private static func readableContent(_ value: JSONValue?) throws -> String {
        if let string = value?.string {
            return string
        }
        guard let blocks = value?.anthropicObjects else {
            throw Error.nonportableResult
        }
        let content = try blocks.map { block in
            guard block[AnthropicToolUseParam.Key.type.rawValue]?.string == AnthropicTextParamType.text.rawValue,
                let content = block[AnthropicTextParam.Key.text.rawValue]?.string
            else {
                throw Error.nonportableResult
            }
            let metadata = Set(block.keys).subtracting(["type", "text", "cache_control"])
            return metadata.isEmpty ? content : try jsonText(block)
        }
        return content.joined(separator: "\n")
    }

    private static func isServerResult(_ block: [String: JSONValue]) -> Bool {
        guard let type = block[AnthropicToolUseParam.Key.type.rawValue]?.string else {
            return false
        }
        return serverResultTypes.contains(type)
    }

    private static func nonempty(_ value: JSONValue?) -> String? {
        guard let string = value?.string, !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func text(_ value: String) throws -> [String: JSONValue] {
        try WireObject(AnthropicTextParam(text: value, type: .text).wireJSON()).additionalFields(excluding: [])
    }

    private static func jsonText(_ value: [String: JSONValue]) throws -> String {
        let data = try anthropicJSON(value).serializedData()
        // The exact JSON codec emits UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }
}
