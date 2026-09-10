import Foundation

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

    package static func anthropic(_ root: [String: Any]) throws -> [String: Any] {
        guard let messages = root["messages"] as? [[String: Any]] else {
            return root
        }
        let blocks = messages.flatMap { message -> [[String: Any]] in
            (message["content"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        }
        let calls = try serverCalls(in: blocks)
        guard !calls.isEmpty || blocks.contains(where: isServerResult) else {
            return root
        }
        try validateResults(in: blocks, calls: calls)
        var result = root
        result["messages"] = try messages.map { message in
            guard let content = message["content"] as? [Any] else {
                return message
            }
            var rewritten = message
            rewritten["content"] = try content.map { value -> Any in
                guard let block = value as? [String: Any] else {
                    throw Error.invalidServerHistory
                }
                return try projectedBlock(block, calls: calls)
            }
            return rewritten
        }
        return result
    }

    private static func serverCalls(
        in blocks: [[String: Any]]
    ) throws -> [String: HistoricalServerToolCall] {
        var calls: [String: HistoricalServerToolCall] = [:]
        let clientIDs = Set(
            blocks.filter { $0["type"] as? String == "tool_use" }.compactMap { $0["id"] as? String }
        )
        for (position, block) in blocks.enumerated()
        where block["type"] as? String == "server_tool_use" {
            guard let id = nonempty(block["id"]),
                let name = nonempty(block["name"]),
                let input = block["input"] as? [String: Any],
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
        in blocks: [[String: Any]],
        calls: [String: HistoricalServerToolCall]
    ) throws {
        var completed: Set<String> = []
        for (position, block) in blocks.enumerated() {
            let id = block["tool_use_id"] as? String
            let serverResult = isServerResult(block)
            let clientResult = block["type"] as? String == "tool_result"
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
        _ block: [String: Any],
        calls: [String: HistoricalServerToolCall]
    ) throws -> [String: Any] {
        if block["type"] as? String == "server_tool_use" {
            if let id = block["id"] as? String, let call = calls[id] {
                return text("[Previous server tool: \(call.name)]\nInput: \(call.input)")
            }
        }
        guard let id = block["tool_use_id"] as? String, let call = calls[id],
            isServerResult(block) || block["type"] as? String == "tool_result"
        else {
            return block
        }
        if block["type"] as? String == "web_search_tool_result" {
            return text(try PortableWebSearchHistory.anthropicResultText(block))
        }
        if let error = block["is_error"], !(error is Bool) {
            throw Error.invalidServerHistory
        }
        let state = block["is_error"] as? Bool == true ? "error" : "result"
        let content = try readableContent(block["content"])
        return text("[Previous server tool \(state): \(call.name)]\n\(content)")
    }

    private static func readableContent(_ value: Any?) throws -> String {
        if let string = value as? String {
            return string
        }
        guard let blocks = value as? [[String: Any]] else {
            throw Error.nonportableResult
        }
        let content = try blocks.map { block in
            guard block["type"] as? String == "text", let content = block["text"] as? String else {
                throw Error.nonportableResult
            }
            let metadata = Set(block.keys).subtracting(["type", "text", "cache_control"])
            return metadata.isEmpty ? content : try jsonText(block)
        }
        return content.joined(separator: "\n")
    }

    private static func isServerResult(_ block: [String: Any]) -> Bool {
        guard let type = block["type"] as? String else {
            return false
        }
        return serverResultTypes.contains(type)
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func text(_ value: String) -> [String: Any] {
        ["type": "text", "text": value]
    }

    private static func jsonText(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        // JSONSerialization guarantees UTF-8; no empty-history fallback is needed.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }
}
