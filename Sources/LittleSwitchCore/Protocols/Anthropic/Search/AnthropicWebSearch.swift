import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import LittleSwitchWire

package enum AnthropicWebSearch {
    enum Error: Swift.Error, Equatable { case invalidMessage }
    enum FollowUpMode { case result, terminalError }

    static let toolName = "web_search"

    static func prepare(
        body: Data, targetModel: String, configuration: WebSearchConfiguration
    ) throws -> PreparedWebSearchRequest? {
        let object = try PortableToolHistory.anthropic(object(from: body))
        guard let toolsValue = object[AnthropicCountTokensProjection.Key.tools.rawValue] else { return nil }
        guard let tools = toolsValue.anthropicObjects else { throw Error.invalidMessage }
        guard let builtInTool = try builtInSearchTool(in: tools) else { return nil }
        let routing = try anthropicDecode(AnthropicRoutingRequest.self, from: anthropicJSON(object))
        guard !routing.model.isEmpty else { throw Error.invalidMessage }

        try requireBridgeableCallers(for: builtInTool)
        let requestedUses = builtInTool[AnthropicSearchToolConfiguration.Key.maxUses.rawValue]?.integer.flatMap {
            $0 > 0 ? $0 : nil
        }
        let maximumUses = requestedUses.map { min(configuration.maximumUses, $0) } ?? configuration.maximumUses
        let searchOptions = try searchOptions(from: builtInTool)
        let clientTools = tools.filter { !isBuiltInSearchTool($0) }
        let privateToolName =
            configuration.provider == .disabled
            ? nil
            : privateSearchToolName(
                clientTools: clientTools,
                messages: object[AnthropicCountTokensProjection.Key.messages.rawValue]?.anthropicObjects ?? []
            )
        var privateTools = clientTools
        if let privateToolName { privateTools.insert(try privateSearchTool(name: privateToolName), at: 0) }

        var upstream = object
        upstream[AnthropicRoutingRequest.Key.model.rawValue] = .string(targetModel)
        upstream["stream"] = .boolean(object["stream"]?.boolean ?? false)
        upstream[AnthropicCountTokensProjection.Key.tools.rawValue] = .array(privateTools.map(anthropicJSON))
        let forcedChoice = upstream[AnthropicCountTokensProjection.Key.toolChoice.rawValue]?.anthropicObject
        let forcedChoiceType = forcedChoice?[AnthropicNamedToolChoice.Key.type.rawValue]?.string
        let forcesBuiltInSearch =
            try forcedChoiceType.map {
                try builtInSearchTool(in: [[AnthropicToolDefinition.Key.type.rawValue: .string($0)]]) != nil
            } ?? false
        let forcesNamedSearch =
            forcedChoiceType == AnthropicNamedToolChoiceType.tool.rawValue
            && forcedChoice?[AnthropicNamedToolChoice.Key.name.rawValue]?.string == toolName
            && !clientTools.contains { $0[AnthropicToolDefinition.Key.name.rawValue]?.string == toolName }
        if forcesBuiltInSearch || forcesNamedSearch {
            if let privateToolName {
                upstream[AnthropicCountTokensProjection.Key.toolChoice.rawValue] =
                    try AnthropicNamedToolChoice(name: privateToolName, type: .tool).wireJSON()
            } else if clientTools.isEmpty {
                upstream.removeValue(forKey: AnthropicCountTokensProjection.Key.toolChoice.rawValue)
            } else {
                upstream[AnthropicCountTokensProjection.Key.toolChoice.rawValue] =
                    try AnthropicAutomaticToolChoice(type: .auto).wireJSON()
            }
        } else if privateTools.isEmpty {
            upstream.removeValue(forKey: AnthropicCountTokensProjection.Key.toolChoice.rawValue)
        }
        try ProviderToolRequestPolicy.anthropic(upstream)
        return PreparedWebSearchRequest(
            upstreamBody: try data(from: upstream),
            originalModel: routing.model,
            streaming: object["stream"]?.boolean ?? false,
            maximumUses: privateToolName == nil ? 0 : maximumUses,
            searchOptions: searchOptions,
            privateToolName: privateToolName
        )
    }

    static func parseModelTurn(
        _ body: Data, privateToolName: String? = toolName
    ) throws -> AnthropicModelTurn {
        let document: WireDocument<AnthropicMessage>
        do { document = try WireCodec.decode(AnthropicMessage.self, from: body) } catch { throw Error.invalidMessage }
        let message = document.value
        guard !message.id.isEmpty, let usage = message.usage else { throw Error.invalidMessage }
        var searchCall: WebSearchToolCall?
        for raw in message.content {
            let block = try anthropicDecode(AnthropicIncomingContentBlock.self, from: raw)
            if case .toolUse(let tool) = block, tool.name == privateToolName {
                guard !tool.id.isEmpty else { throw Error.invalidMessage }
                if searchCall == nil {
                    searchCall = WebSearchToolCall(
                        id: tool.id,
                        query: tool.input?.object?[AnthropicPrivateSearchInput.Key.query.rawValue]?.string ?? "")
                }
            }
        }
        let stopSequence: Data?
        switch message.stopSequence {
        case .absent: stopSequence = nil
        case .null: stopSequence = try JSONValue.null.serializedData()
        case .value(let value): stopSequence = try value.serializedData()
        }
        return AnthropicModelTurn(
            id: message.id,
            contentJSON: try JSONValue.array(message.content).serializedData(),
            stopReason: message.stopReason.value?.rawValue,
            stopSequenceJSON: stopSequence,
            usage: try parseUsage(usage),
            webSearchCall: searchCall
        )
    }

    private static func privateSearchTool(name: String) throws -> JSONObject {
        let tool = AnthropicToolDefinition(
            description:
                "Search the web for current information. Use this to find up-to-date information about any topic.",
            inputSchema: AnthropicPrivateSearchInput.schema,
            name: name
        )
        return try WireObject(tool.wireJSON()).additionalFields(excluding: [])
    }

    static func object(from data: Data) throws -> JSONObject {
        do {
            let document = try WireCodec.decode(JSONValue.self, from: data)
            guard let object = document.value.anthropicObject else { throw Error.invalidMessage }
            return object
        } catch { throw Error.invalidMessage }
    }

    static func data(from object: JSONObject) throws -> Data {
        try anthropicJSON(object).serializedData()
    }

    static func fragmentObject(from data: Data?) throws -> JSONValue {
        guard let data else { return .null }
        do { return try WireCodec.decode(JSONValue.self, from: data).value } catch { throw Error.invalidMessage }
    }

    static func responseContent(
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        privateToolName: String? = toolName
    ) throws -> [JSONObject] {
        var content: [JSONObject] = []
        for trace in traces {
            let traceContent = try publicTraceContent(trace.publicContentJSON, privateToolName: privateToolName)
            content += traceContent.beforeSearch
            let call = AnthropicServerToolUseBlock(
                caller: .value(try AnthropicDirectCaller(type: .direct).wireJSON()),
                id: trace.toolUseID,
                input: AnthropicPrivateSearchInput.value(query: trace.query),
                name: .known(.webSearch),
                type: .serverToolUse
            )
            content.append(try WireObject(call.wireJSON()).additionalFields(excluding: []))
            let result = AnthropicWebSearchToolResultBlock(
                caller: .value(try AnthropicDirectCaller(type: .direct).wireJSON()),
                content: try nativeResultContent(trace),
                toolUseId: trace.toolUseID,
                type: .webSearchToolResult
            )
            content.append(try WireObject(result.wireJSON()).additionalFields(excluding: []))
            content += traceContent.afterSearch
        }
        guard let finalContent = try fragmentObject(from: finalTurn.contentJSON).anthropicObjects else {
            throw Error.invalidMessage
        }
        content.append(
            contentsOf: try finalContent.compactMap { block in
                guard !isPrivateSearchBlock(block, privateToolName: privateToolName) else { return nil }
                return try AnthropicPublicSanitizer.block(block)
            })
        return content
    }

    private static func publicTraceContent(
        _ data: Data?, privateToolName: String?
    ) throws -> (beforeSearch: [JSONObject], afterSearch: [JSONObject]) {
        guard let data else { return ([], []) }
        guard let blocks = try fragmentObject(from: data).anthropicObjects else { throw Error.invalidMessage }
        var beforeSearch: [JSONObject] = []
        var afterSearch: [JSONObject] = []
        var foundPrivateSearch = false
        for block in blocks {
            guard block[AnthropicToolUseBlock.Key.type.rawValue]?.string != nil else { throw Error.invalidMessage }
            if isPrivateSearchBlock(block, privateToolName: privateToolName) {
                foundPrivateSearch = true
                continue
            }
            guard block[AnthropicToolUseBlock.Key.type.rawValue]?.string != AnthropicToolUseBlockType.toolUse.rawValue,
                let publicBlock = try AnthropicPublicSanitizer.block(block)
            else { continue }
            if foundPrivateSearch { afterSearch.append(publicBlock) } else { beforeSearch.append(publicBlock) }
        }
        return (beforeSearch, afterSearch)
    }

    static func appendEvent(name: String, payload: JSONValue, to stream: inout Data) throws {
        stream.append(Data("event: \(name)\ndata: ".utf8))
        stream.append(try payload.serializedData())
        stream.append(Data("\n\n".utf8))
    }
}
