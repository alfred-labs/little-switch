import Foundation
import LittleSwitchWire

package enum ResponsesChatCompletionsMode: Equatable, Sendable {
    case buffered
    case streaming(toolStream: Bool)
}

private struct ChatCompletionsTerminalProjection {
    let status: ResponsesStreamTerminal
    let incompleteReason: OpenAIResponsesIncompleteDetailsReason?
    let error: OpenAIResponsesWireError?

    var wireStatus: OpenAIResponsesStatus {
        switch status {
        case .completed: .completed
        case .incomplete: .incomplete
        case .failed: .failed
        }
    }
}

package enum OpenAIResponsesChatCompletions {
    enum Error: Swift.Error, Equatable {
        case invalidRequest
        case invalidResponse
        case contextLengthExceeded
    }

    package static func prepare(
        body: Data,
        targetModel: String,
        providerID: UUID? = nil,
        mode: ResponsesChatCompletionsMode = .buffered,
        inheritedToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        inheritedDeclaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        inheritedToolNameCatalog: ProviderToolNameCatalog? = nil,
        inheritedToolSearchContract: ResponsesClientToolSearchContract? = nil,
        originalBody: Data? = nil
    ) throws -> PreparedResponsesChatCompletionsRequest {
        let search: PreparedResponsesToolSearchRequest?
        do {
            search =
                inheritedToolSearchContract == nil
                ? try OpenAIResponsesToolSearch.prepare(body: body, originalBody: originalBody) : nil
        } catch {
            throw Error.invalidRequest
        }
        guard
            let source = object(search?.upstreamBody ?? body),
            !ResponsesConversationReferences.hasServerState(in: source),
            let originalModel = nonemptyString(source["model"]),
            !targetModel.isEmpty
        else {
            throw Error.invalidRequest
        }

        let deduplicated = ResponsesHistoryDeduplication.rewritten(source) ?? source
        let root = ResponsesImageTurnCompatibility.rewritten(deduplicated) ?? deduplicated
        // The search bridge may already have flattened the declarations.
        // Retain its bindings for restored history and live output events.
        try validateToolsForChat(root["tools"] as? [[String: Any]] ?? [])
        let flattened = ResponsesToolNamespaces.flatten(
            tools: root["tools"] as? [[String: Any]] ?? [],
            history: root["input"] as? [[String: Any]] ?? [],
            inheritedBindings: inheritedToolBindings,
            inheritedDeclaredBindings: inheritedDeclaredToolBindings
        )
        let toolBindings = flattened.bindings
        let declaredToolBindings = flattened.declaredBindings
        var request: [String: Any] = ["model": targetModel]
        try ResponsesChatCompletionsOptions.copy(from: root, to: &request)
        let converted = flattened.tools.compactMap(chatTool)
        if !converted.isEmpty {
            request["tools"] = converted
        }
        let requestNames = try ProviderToolContractCatalog(wire: .chatCompletions, requestBody: data(request))
            .nameCatalog
        if request["tools"] != nil || (root["tool_choice"] as? [String: Any])?["type"] as? String == "allowed_tools" {
            request["tool_choice"] = try chatToolChoice(root["tool_choice"], bindings: declaredToolBindings)
        }
        try ChatAllowedToolSelection.apply(to: &request)

        // Only declarations actually sent to this provider keep custom history
        // active. Preserve the original name catalog for excluded-name safety.
        let selectedCustomNames = Set(
            (request["tools"] as? [[String: Any]] ?? []).compactMap {
                ($0["custom"] as? [String: Any])?["name"] as? String
            })
        var history = root
        history["tools"] = flattened.tools.filter {
            $0["type"] as? String == "custom"
                && ($0["name"] as? String).map(selectedCustomNames.contains) == true
        }
        do {
            history = try ResponsesCustomToolHistory.normalized(history, bindings: toolBindings)
        } catch {
            throw Error.invalidRequest
        }
        guard let input = history["input"] else { throw Error.invalidRequest }
        var messages: [[String: Any]] = []
        if let instructions = nonemptyString(root["instructions"]) {
            messages.append(["role": "system", "content": instructions])
        }
        let droppedMailCount = try ResponsesChatCompletionsHistory.append(
            input,
            to: &messages,
            bindings: toolBindings,
            providerID: providerID
        )
        guard !messages.isEmpty else { throw Error.invalidRequest }
        request["messages"] = messages
        let toolNameCatalog = ProviderToolNameCatalog(
            declared: requestNames.declared.union(inheritedToolNameCatalog?.declared ?? []),
            historical: ProviderToolNameCatalog.history(in: request, wire: .chatCompletions)
                .union(inheritedToolNameCatalog?.historical ?? []))
        switch mode {
        case .buffered:
            request["stream"] = false
        case .streaming(let toolStream):
            request["stream"] = true
            request["stream_options"] = ["include_usage": true]
            let toolStreamingEnabled =
                toolStream && request["tools"] != nil
                && supportsZAIStreamingTools(modelID: targetModel)
            if toolStreamingEnabled {
                request["tool_stream"] = true
            }
        }

        let upstreamBody = try outboundData(request)
        return PreparedResponsesChatCompletionsRequest(
            upstreamBody: upstreamBody,
            originalBody: originalBody ?? search?.originalBody ?? body,
            originalModel: originalModel,
            providerID: providerID,
            streaming: root["stream"] as? Bool ?? false,
            toolBindings: toolBindings,
            declaredToolBindings: declaredToolBindings,
            toolNameCatalog: toolNameCatalog,
            allowedToolIdentities: try ProviderToolContractCatalog(wire: .chatCompletions, requestBody: upstreamBody)
                .allowedIdentities,
            droppedMailCount: droppedMailCount,
            toolSearchContract: inheritedToolSearchContract ?? search?.contract
        )
    }
}

extension OpenAIResponsesChatCompletions {
    static func terminalStatus(responseBody: Data) throws -> ResponsesStreamTerminal {
        guard let choice = try decodedChat(responseBody).choices.first else {
            throw Error.invalidResponse
        }
        let terminal = try terminalProjection(choice.finishReason)
        return terminal.status
    }

    static func project(
        responseBody: Data,
        prepared: PreparedResponsesChatCompletionsRequest
    ) throws -> Data {
        let chat = try decodedChat(responseBody)
        guard let choice = chat.choices.first else {
            throw Error.invalidResponse
        }

        let chatID = nonemptyString(chat.id.value) ?? "chatcmpl_little_switch"
        let responseID = chatID.hasPrefix("resp_") ? chatID : "resp_\(chatID)"
        let created = (try? chat.created.value?.integerValue()) ?? 0
        let terminal = try terminalProjection(choice.finishReason)
        let rawOutput = try responseOutput(
            message: choice.message,
            responseID: responseID,
            bindings: prepared.toolBindings,
            resolver: ProviderToolNamespaceResolver(
                declaredBindings: prepared.declaredToolBindings,
                nameCatalog: prepared.toolNameCatalog
            ),
            providerID: prepared.providerID
        )
        let output = try rawOutput.map { item in
            try prepared.toolSearchContract?.projectItem(item) ?? item
        }
        let usage = try responsesUsage(chat.usage.value)
        let response = try OpenAIResponsesResponse(
            completedAt: .value(JSONNumber(created)),
            createdAt: JSONNumber(created),
            error: terminal.error.map { .value($0) } ?? .null,
            id: responseID,
            incompleteDetails: terminal.incompleteReason.map {
                .value(try OpenAIResponsesIncompleteDetails(reason: $0).wireJSON())
            } ?? .null,
            object: .response,
            output: output.map(WireJSONCompatibility.value),
            status: terminal.wireStatus,
            usage: .value(OpenAIResponsesWireUsage(wireJSON: WireJSONCompatibility.value(responsesPublicUsage(usage)))),
            additionalFields: responseEcho(prepared)
        )
        let data = try WireCodec.encode(response)
        return prepared.streaming
            ? try OpenAIResponsesStreaming.encode(completed: WireJSONCompatibility.fields(data))
            : data
    }

    private static func terminalProjection(
        _ finishReason: OpenAIChatCompletionFinishReason
    ) throws -> ChatCompletionsTerminalProjection {
        switch finishReason {
        case .stop, .toolCalls:
            ChatCompletionsTerminalProjection(
                status: .completed,
                incompleteReason: nil,
                error: nil
            )
        case .length:
            ChatCompletionsTerminalProjection(
                status: .incomplete,
                incompleteReason: .maxOutputTokens,
                error: nil
            )
        case .sensitive, .contentFilter:
            ChatCompletionsTerminalProjection(
                status: .incomplete,
                incompleteReason: .contentFilter,
                error: nil
            )
        case .modelContextWindowExceeded, .networkError:
            ChatCompletionsTerminalProjection(
                status: .failed,
                incompleteReason: nil,
                error: OpenAIResponsesWireError(
                    code: .known(finishReason == .modelContextWindowExceeded ? .contextLengthExceeded : .serverError),
                    message: "Internal server error")
            )
        case .functionCall:
            throw Error.invalidResponse
        }
    }

    private static func validateToolsForChat(_ tools: [[String: Any]]) throws {
        do { try ProviderToolContractCatalog.validateResponsesDeclarations(tools) } catch { throw Error.invalidRequest }
    }

    private static func decodedChat(_ data: Data) throws -> OpenAIChatCompletion {
        do {
            return try WireCodec.decode(OpenAIChatCompletion.self, from: data).value
        } catch {
            throw Error.invalidResponse
        }
    }

    private static func chatTool(_ tool: [String: Any]) -> [String: Any]? {
        guard let type = tool["type"] as? String,
            let kind = ProviderToolContractCatalog.Kind(rawValue: type),
            let name = nonemptyString(tool["name"])
        else {
            return nil
        }
        var function: [String: Any] = ["name": name]
        copy("description", from: tool, to: &function)
        if kind == .function {
            copy("parameters", from: tool, to: &function)
            copy("strict", from: tool, to: &function)
        } else {
            copy("format", from: tool, to: &function)
        }
        return ["type": type, type: function]
    }

    private static func copy(
        _ key: String,
        from source: [String: Any],
        to destination: inout [String: Any]
    ) {
        if let value = source[key] {
            destination[key] = value
        }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        try? WireJSONCompatibility.fields(data)
    }

    private static func data(_ object: [String: Any]) throws -> Data {
        try WireJSONCompatibility.data(object)
    }

    private static func outboundData(_ request: [String: Any]) throws -> Data {
        // The history builder validates roles and required fields before this
        // internal encoding boundary. Keep the resulting SDK record checks.
        var envelope = try OpenAIChatRequestEnvelope(wireJSON: WireJSONCompatibility.value(request))
        envelope.messages = try envelope.messages.map { value in
            let message = try OpenAIChatRequestMessage(wireJSON: value)
            if case .unknown = message { throw Error.invalidRequest }
            return try message.wireJSON()
        }
        return try WireCodec.encode(envelope)
    }
}
