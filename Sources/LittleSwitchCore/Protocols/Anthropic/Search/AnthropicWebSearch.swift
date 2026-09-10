import Foundation
import LittleSwitchSearch

package enum AnthropicWebSearch {
    enum Error: Swift.Error, Equatable {
        case invalidMessage
    }

    enum FollowUpMode {
        case result
        case terminalError
    }

    static let toolName = "web_search"

    static func prepare(
        body: Data,
        targetModel: String,
        configuration: WebSearchConfiguration
    ) throws -> PreparedWebSearchRequest? {
        let object = try PortableToolHistory.anthropic(object(from: body))
        guard let toolsValue = object["tools"] else {
            return nil
        }
        guard let tools = toolsValue as? [[String: Any]] else {
            throw Error.invalidMessage
        }
        guard let builtInTool = try builtInSearchTool(in: tools) else {
            return nil
        }
        guard let originalModel = object["model"] as? String,
            !originalModel.isEmpty
        else {
            throw Error.invalidMessage
        }

        try requireBridgeableCallers(for: builtInTool)
        let requestedUses = positiveInteger(builtInTool["max_uses"])
        let maximumUses =
            requestedUses.map { min(configuration.maximumUses, $0) }
            ?? configuration.maximumUses
        let searchOptions = try searchOptions(from: builtInTool)
        let clientTools = tools.filter { !isBuiltInSearchTool($0) }
        let privateToolName: String?
        if configuration.provider == .disabled {
            privateToolName = nil
        } else {
            privateToolName = privateSearchToolName(
                clientTools: clientTools,
                messages: object["messages"] as? [[String: Any]] ?? []
            )
        }
        var privateTools = clientTools
        if let privateToolName {
            privateTools.insert(privateSearchTool(name: privateToolName), at: 0)
        }

        var upstream = object
        upstream["model"] = targetModel
        upstream["stream"] = object["stream"] as? Bool ?? false
        upstream["tools"] = privateTools
        // A forced built-in search choice ({"type": "web_search_20250305"})
        // names a tool the upstream never sees once the bridge swaps in the
        // private replacement; rewrite it onto that replacement so the
        // forced intent survives instead of failing the whole request.
        let forcedChoice = upstream["tool_choice"] as? [String: Any]
        let forcedChoiceType = forcedChoice?["type"] as? String
        let forcesBuiltInSearch =
            try forcedChoiceType.map {
                try builtInSearchTool(in: [["type": $0]]) != nil
            } ?? false
        let forcesNamedSearch =
            forcedChoiceType == "tool"
            && forcedChoice?["name"] as? String == toolName
            && !clientTools.contains { $0["name"] as? String == toolName }
        if forcesBuiltInSearch || forcesNamedSearch {
            upstream["tool_choice"] =
                privateToolName.map { ["type": "tool", "name": $0] }
                ?? (clientTools.isEmpty ? nil : ["type": "auto"])
        } else if privateTools.isEmpty {
            upstream.removeValue(forKey: "tool_choice")
        }
        try ProviderToolRequestPolicy.anthropic(upstream)
        return PreparedWebSearchRequest(
            upstreamBody: try data(from: upstream),
            originalModel: originalModel,
            streaming: object["stream"] as? Bool ?? false,
            maximumUses: privateToolName == nil ? 0 : maximumUses,
            searchOptions: searchOptions,
            privateToolName: privateToolName
        )
    }

    static func parseModelTurn(
        _ body: Data,
        privateToolName: String? = toolName
    ) throws -> AnthropicModelTurn {
        let object = try object(from: body)
        guard let id = object["id"] as? String, !id.isEmpty,
            let rawContent = object["content"] as? [Any],
            let usageObject = object["usage"] as? [String: Any]
        else {
            throw Error.invalidMessage
        }

        var searchCall: WebSearchToolCall?
        for value in rawContent {
            guard let block = value as? [String: Any], block["type"] is String else {
                throw Error.invalidMessage
            }
            guard isPrivateSearchBlock(block, privateToolName: privateToolName) else {
                continue
            }
            guard let toolID = block["id"] as? String, !toolID.isEmpty else {
                throw Error.invalidMessage
            }
            if searchCall == nil {
                let input = block["input"] as? [String: Any]
                searchCall = WebSearchToolCall(
                    id: toolID,
                    query: input?["query"] as? String ?? ""
                )
            }
        }

        let stopReason: String?
        if let value = object["stop_reason"], !(value is NSNull) {
            guard let value = value as? String else {
                throw Error.invalidMessage
            }
            stopReason = value
        } else {
            stopReason = nil
        }
        let stopSequenceJSON: Data?
        if let stopSequence = object["stop_sequence"] {
            stopSequenceJSON = try fragmentData(from: stopSequence)
        } else {
            stopSequenceJSON = nil
        }
        return AnthropicModelTurn(
            id: id,
            contentJSON: try fragmentData(from: rawContent),
            stopReason: stopReason,
            stopSequenceJSON: stopSequenceJSON,
            usage: try parseUsage(usageObject),
            webSearchCall: searchCall
        )
    }

}

extension AnthropicWebSearch {
    private static func privateSearchTool(name: String) -> [String: Any] {
        [
            "name": name,
            "description":
                "Search the web for current information. Use this to find up-to-date information about any topic.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query to look up on the web",
                    ]
                ],
                "required": ["query"],
            ],
        ]
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        guard let value = value as? Int, value > 0 else {
            return nil
        }
        return value
    }

    static func object(from data: Data) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Error.invalidMessage
            }
            return object
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidMessage
        }
    }

    static func data(from object: [String: Any]) throws -> Data {
        try serialize(
            object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) { value, options in
            try JSONSerialization.data(withJSONObject: value, options: options)
        }
    }

    private static func fragmentData(from value: Any) throws -> Data {
        try serialize(
            value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        ) { value, options in
            try JSONSerialization.data(withJSONObject: value, options: options)
        }
    }

    package static func serialize(
        _ value: Any,
        options: JSONSerialization.WritingOptions,
        using serializer: (Any, JSONSerialization.WritingOptions) throws -> Data
    ) throws -> Data {
        let validationRoot: Any = options.contains(.fragmentsAllowed) ? [value] : value
        guard JSONSerialization.isValidJSONObject(validationRoot) else {
            throw Error.invalidMessage
        }
        do {
            return try serializer(value, options)
        } catch {
            throw Error.invalidMessage
        }
    }

    static func fragmentObject(from data: Data?) throws -> Any {
        guard let data else {
            return NSNull()
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Error.invalidMessage
        }
    }

    static func responseContent(
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        privateToolName: String? = toolName
    ) throws -> [[String: Any]] {
        var content: [[String: Any]] = []
        for trace in traces {
            let traceContent = try publicTraceContent(trace.publicContentJSON, privateToolName: privateToolName)
            content += traceContent.beforeSearch
            content.append([
                "type": "server_tool_use",
                "id": trace.toolUseID,
                "name": toolName,
                "input": ["query": trace.query],
                "caller": ["type": "direct"],
            ])
            let resultContent = try nativeResultContent(trace)
            content.append([
                "type": "web_search_tool_result",
                "tool_use_id": trace.toolUseID,
                "content": resultContent,
                "caller": ["type": "direct"],
            ])
            content += traceContent.afterSearch
        }

        do {
            guard
                let finalContent = try JSONSerialization.jsonObject(
                    with: finalTurn.contentJSON,
                    options: [.fragmentsAllowed]
                ) as? [[String: Any]]
            else {
                throw Error.invalidMessage
            }
            content.append(
                contentsOf: try finalContent.compactMap { block in
                    guard !isPrivateSearchBlock(block, privateToolName: privateToolName) else {
                        return nil
                    }
                    return try AnthropicPublicSanitizer.block(block)
                }
            )
            return content
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidMessage
        }
    }

    private static func publicTraceContent(
        _ data: Data?,
        privateToolName: String?
    ) throws -> (beforeSearch: [[String: Any]], afterSearch: [[String: Any]]) {
        guard let data else {
            return ([], [])
        }
        do {
            guard
                let blocks = try JSONSerialization.jsonObject(
                    with: data,
                    options: [.fragmentsAllowed]
                ) as? [[String: Any]]
            else {
                throw Error.invalidMessage
            }
            var beforeSearch: [[String: Any]] = []
            var afterSearch: [[String: Any]] = []
            var foundPrivateSearch = false
            for block in blocks {
                guard block["type"] is String else {
                    throw Error.invalidMessage
                }
                if isPrivateSearchBlock(block, privateToolName: privateToolName) {
                    foundPrivateSearch = true
                    continue
                }
                guard block["type"] as? String != "tool_use",
                    let publicBlock = try AnthropicPublicSanitizer.block(block)
                else {
                    continue
                }
                if foundPrivateSearch {
                    afterSearch.append(publicBlock)
                } else {
                    beforeSearch.append(publicBlock)
                }
            }
            return (beforeSearch, afterSearch)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidMessage
        }
    }

    static func appendStreamingBlock(
        _ block: [String: Any],
        index: Int,
        to stream: inout Data
    ) throws {
        switch block["type"] as? String {
        case "text":
            try appendStreamingText(block, index: index, to: &stream)
        case "thinking":
            try appendStreamingThinking(block, index: index, to: &stream)
        case "server_tool_use":
            guard let input = block["input"] as? [String: Any] else {
                throw Error.invalidMessage
            }
            try appendStreamingTool(
                block,
                input: input,
                index: index,
                to: &stream
            )
        case "tool_use":
            guard let input = block["input"] as? [String: Any] else {
                throw Error.invalidMessage
            }
            try appendStreamingTool(block, input: input, index: index, to: &stream)
        default:
            try appendContentStart(block, index: index, to: &stream)
        }
        try appendEvent(
            name: "content_block_stop",
            payload: ["type": "content_block_stop", "index": index],
            to: &stream
        )
    }

    private static func appendStreamingText(
        _ block: [String: Any],
        index: Int,
        to stream: inout Data
    ) throws {
        guard let text = block["text"] as? String else {
            throw Error.invalidMessage
        }
        var startBlock = block
        startBlock["text"] = ""
        try appendContentStart(startBlock, index: index, to: &stream)
        try appendEvent(
            name: "content_block_delta",
            payload: [
                "type": "content_block_delta",
                "index": index,
                "delta": ["type": "text_delta", "text": text],
            ],
            to: &stream
        )
    }

    private static func appendStreamingThinking(
        _ block: [String: Any],
        index: Int,
        to stream: inout Data
    ) throws {
        guard let thinking = block["thinking"] as? String else {
            throw Error.invalidMessage
        }
        let signature = block["signature"] as? String
        var startBlock = block
        startBlock["thinking"] = ""
        if block["signature"] != nil {
            startBlock["signature"] = ""
        }
        try appendContentStart(startBlock, index: index, to: &stream)
        if !thinking.isEmpty {
            try appendEvent(
                name: "content_block_delta",
                payload: [
                    "type": "content_block_delta",
                    "index": index,
                    "delta": ["type": "thinking_delta", "thinking": thinking],
                ],
                to: &stream
            )
        }
        if let signature, !signature.isEmpty {
            try appendEvent(
                name: "content_block_delta",
                payload: [
                    "type": "content_block_delta",
                    "index": index,
                    "delta": ["type": "signature_delta", "signature": signature],
                ],
                to: &stream
            )
        }
    }

    private static func appendStreamingTool(
        _ block: [String: Any],
        input: [String: Any],
        index: Int,
        to stream: inout Data
    ) throws {
        var startBlock = block
        startBlock["input"] = [:]
        try appendContentStart(startBlock, index: index, to: &stream)
        try appendInputJSONDelta(input, index: index, to: &stream)
    }

    private static func appendContentStart(
        _ block: [String: Any],
        index: Int,
        to stream: inout Data
    ) throws {
        try appendEvent(
            name: "content_block_start",
            payload: [
                "type": "content_block_start",
                "index": index,
                "content_block": block,
            ],
            to: &stream
        )
    }

    private static func appendInputJSONDelta(
        _ input: [String: Any],
        index: Int,
        to stream: inout Data
    ) throws {
        let inputData = try data(from: input)
        // JSONSerialization output is always valid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        let partialJSON = String(decoding: inputData, as: UTF8.self)
        try appendEvent(
            name: "content_block_delta",
            payload: [
                "type": "content_block_delta",
                "index": index,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": partialJSON,
                ],
            ],
            to: &stream
        )
    }

    static func appendEvent(
        name: String,
        payload: [String: Any],
        to stream: inout Data
    ) throws {
        stream.append(Data("event: \(name)\ndata: ".utf8))
        stream.append(try data(from: payload))
        stream.append(Data("\n\n".utf8))
    }
}
