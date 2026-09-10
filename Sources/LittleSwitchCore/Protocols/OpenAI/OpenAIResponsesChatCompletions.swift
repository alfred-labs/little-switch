import Foundation

package enum ResponsesChatCompletionsMode: Equatable, Sendable {
    case buffered
    case streaming(toolStream: Bool)
}

private struct ChatCompletionsTerminalProjection {
    let status: ResponsesStreamTerminal
    let incompleteReason: String?
    let error: [String: String]?
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
        mode: ResponsesChatCompletionsMode = .buffered,
        inheritedToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
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
            let root = object(search?.upstreamBody ?? body),
            !ResponsesConversationReferences.hasServerState(in: root),
            let originalModel = nonemptyString(root["model"]),
            !targetModel.isEmpty,
            let input = root["input"]
        else {
            throw Error.invalidRequest
        }

        var messages: [[String: Any]] = []
        if let instructions = nonemptyString(root["instructions"]) {
            messages.append(["role": "system", "content": instructions])
        }
        // The search bridge may already have flattened the declarations.
        // Retain its bindings for restored history and live output events.
        var toolBindings = inheritedToolBindings
        try validateToolsForChat(root["tools"] as? [[String: Any]] ?? [])
        let flattened = ResponsesToolNamespaces.flatten(
            tools: root["tools"] as? [[String: Any]] ?? [],
            history: root["input"] as? [[String: Any]] ?? []
        )
        for (name, binding) in flattened.bindings {
            toolBindings[name] = binding
        }
        let droppedMailCount = try appendInput(
            input,
            to: &messages,
            bindings: toolBindings
        )
        guard !messages.isEmpty else {
            throw Error.invalidRequest
        }

        var request: [String: Any] = [
            "model": targetModel,
            "messages": messages,
        ]
        copy("parallel_tool_calls", from: root, to: &request)
        copy("temperature", from: root, to: &request)
        copy("top_p", from: root, to: &request)
        if let maximum = root["max_output_tokens"] {
            request["max_tokens"] = maximum
        }
        let converted = flattened.tools.compactMap(chatTool)
        if !converted.isEmpty {
            request["tools"] = converted
        }
        if request["tools"] != nil, let choice = chatToolChoice(root["tool_choice"], bindings: toolBindings) {
            request["tool_choice"] = choice
        }
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

        return PreparedResponsesChatCompletionsRequest(
            upstreamBody: try data(request),
            originalBody: originalBody ?? search?.originalBody ?? body,
            originalModel: originalModel,
            streaming: root["stream"] as? Bool ?? false,
            toolBindings: toolBindings,
            droppedMailCount: droppedMailCount,
            toolSearchContract: inheritedToolSearchContract ?? search?.contract
        )
    }
}

extension OpenAIResponsesChatCompletions {
    static func terminalStatus(responseBody: Data) throws -> ResponsesStreamTerminal {
        guard
            let chat = object(responseBody),
            let choices = chat["choices"] as? [[String: Any]],
            let choice = choices.first
        else {
            throw Error.invalidResponse
        }
        let terminal = try terminalProjection(choice["finish_reason"] as? String)
        return terminal.status
    }

    static func project(
        responseBody: Data,
        prepared: PreparedResponsesChatCompletionsRequest
    ) throws -> Data {
        guard
            let chat = object(responseBody),
            let choices = chat["choices"] as? [[String: Any]],
            let choice = choices.first,
            let message = choice["message"] as? [String: Any],
            let original = object(prepared.originalBody)
        else {
            throw Error.invalidResponse
        }

        let chatID = nonemptyString(chat["id"]) ?? "chatcmpl_little_switch"
        let responseID = chatID.hasPrefix("resp_") ? chatID : "resp_\(chatID)"
        let created = chat["created"] as? Int ?? 0
        let finishReason = choice["finish_reason"] as? String
        let terminal = try terminalProjection(finishReason)
        let rawOutput = try responseOutput(
            message: message,
            responseID: responseID,
            bindings: prepared.toolBindings
        )
        let output = try rawOutput.map { item in
            try prepared.toolSearchContract?.projectItem(item) ?? item
        }
        let usage = try responsesUsage(chat["usage"])
        let incompleteDetails: Any =
            terminal.incompleteReason.map { ["reason": $0] } ?? NSNull()
        let responseError: Any = terminal.error ?? NSNull()

        let response: [String: Any] = [
            "id": responseID,
            "object": "response",
            "created_at": created,
            "completed_at": created,
            "status": terminal.status.rawValue,
            "error": responseError,
            "incomplete_details": incompleteDetails,
            "instructions": original["instructions"] ?? NSNull(),
            "max_output_tokens": original["max_output_tokens"] ?? NSNull(),
            "model": prepared.originalModel,
            "output": output,
            "parallel_tool_calls": original["parallel_tool_calls"] as? Bool ?? true,
            "previous_response_id": original["previous_response_id"] ?? NSNull(),
            "reasoning": original["reasoning"]
                ?? ["effort": NSNull(), "summary": NSNull()],
            "store": original["store"] as? Bool ?? true,
            "temperature": original["temperature"] ?? NSNull(),
            "text": original["text"] ?? ["format": ["type": "text"]],
            "tool_choice": original["tool_choice"] ?? "auto",
            "tools": original["tools"] ?? [],
            "top_p": original["top_p"] ?? NSNull(),
            "truncation": original["truncation"] ?? "disabled",
            "usage": responsesPublicUsage(usage),
            "user": original["user"] ?? NSNull(),
            "metadata": original["metadata"] ?? [:],
        ]
        return prepared.streaming
            ? try OpenAIResponsesStreaming.encode(completed: response)
            : try data(response)
    }

    private static func terminalProjection(
        _ finishReason: String?
    ) throws -> ChatCompletionsTerminalProjection {
        switch finishReason {
        case "stop", "tool_calls":
            ChatCompletionsTerminalProjection(
                status: .completed,
                incompleteReason: nil,
                error: nil
            )
        case "length":
            ChatCompletionsTerminalProjection(
                status: .incomplete,
                incompleteReason: "max_output_tokens",
                error: nil
            )
        case "sensitive":
            ChatCompletionsTerminalProjection(
                status: .incomplete,
                incompleteReason: "content_filter",
                error: nil
            )
        case "model_context_window_exceeded", "network_error":
            ChatCompletionsTerminalProjection(
                status: .failed,
                incompleteReason: nil,
                error: [
                    "code": finishReason == "model_context_window_exceeded"
                        ? "context_length_exceeded"
                        : "server_error",
                    "message": "Internal server error",
                ]
            )
        default:
            throw Error.invalidResponse
        }
    }

    /// Appends the Responses input items as chat messages and reports how many
    /// `agent_message` items carried no readable text and were dropped.
    private static func appendInput(
        _ input: Any,
        to messages: inout [[String: Any]],
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> Int {
        if let text = input as? String {
            messages.append(["role": "user", "content": text])
            return 0
        }
        guard let items = input as? [[String: Any]] else {
            throw Error.invalidRequest
        }
        var droppedMailCount = 0
        for item in items {
            switch item["type"] as? String {
            case "message":
                try appendMessage(item, to: &messages)
            case "function_call":
                guard
                    let callID = nonemptyString(item["call_id"]),
                    let name = nonemptyString(item["name"]),
                    let arguments = item["arguments"] as? String
                else {
                    throw Error.invalidRequest
                }
                let wireName =
                    nonemptyString(item["namespace"]).map {
                        ResponsesToolNamespaces.replayName(
                            bindings: bindings,
                            namespace: $0,
                            name: name
                        )
                    } ?? name
                messages.append([
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": [
                        [
                            "id": callID,
                            "type": "function",
                            "function": ["name": wireName, "arguments": arguments],
                        ]
                    ],
                ])
            case "function_call_output":
                guard
                    let callID = nonemptyString(item["call_id"]),
                    let output = try stringFragment(item["output"])
                else {
                    throw Error.invalidRequest
                }
                messages.append([
                    "role": "tool",
                    "tool_call_id": callID,
                    "content": output,
                ])
            case "reasoning":
                continue
            case "agent_message":
                // Codex's inter-agent mail is inbound context for this model.
                // Tool-authored mail (spawn briefs, send_message) carries its
                // text in encrypted_content; on custom providers that field
                // holds the model-authored plaintext verbatim.
                if let content = ResponsesAgentMail.textContent(item["content"]) {
                    messages.append(["role": "user", "content": content])
                } else {
                    droppedMailCount += 1
                }
                continue
            case "web_search_call":
                guard let message = try? PortableResponsesHistory.message(for: item) else {
                    throw Error.invalidRequest
                }
                try appendMessage(message, to: &messages)
            default:
                throw Error.invalidRequest
            }
        }
        return droppedMailCount
    }

    private static func appendMessage(
        _ item: [String: Any],
        to messages: inout [[String: Any]]
    ) throws {
        guard let role = nonemptyString(item["role"]) else {
            throw Error.invalidRequest
        }
        let chatRole = role == "developer" ? "system" : role
        guard ["system", "user", "assistant"].contains(chatRole) else {
            throw Error.invalidRequest
        }
        if let content = textContent(item["content"]) {
            messages.append(["role": chatRole, "content": content])
            return
        }
        guard let parts = item["content"] as? [[String: Any]],
            let multipart = multipartContent(parts)
        else {
            throw Error.invalidRequest
        }
        messages.append(["role": chatRole, "content": multipart])
    }

    private static func multipartContent(_ parts: [[String: Any]]) -> [[String: Any]]? {
        ResponsesChatCompletionsImageContent.multipart(parts)
    }

    private static func textContent(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        guard let parts = value as? [[String: Any]] else {
            return nil
        }
        let text = parts.compactMap { part -> String? in
            switch part["type"] as? String {
            case "input_text", "output_text":
                part["text"] as? String
            default:
                nil
            }
        }
        guard text.count == parts.count else {
            return nil
        }
        return text.joined(separator: "\n")
    }

    private static func validateToolsForChat(_ tools: [[String: Any]]) throws {
        for tool in tools {
            guard tool["type"] as? String != "custom" else { throw Error.invalidRequest }
            if tool["type"] as? String == "namespace", let children = tool["tools"] as? [[String: Any]] {
                try validateToolsForChat(children)
            }
        }
    }

    private static func chatTool(_ tool: [String: Any]) -> [String: Any]? {
        guard tool["type"] as? String == "function",
            let name = nonemptyString(tool["name"]),
            let parameters = tool["parameters"]
        else {
            return nil
        }
        var function: [String: Any] = [
            "name": name,
            "parameters": parameters,
        ]
        copy("description", from: tool, to: &function)
        copy("strict", from: tool, to: &function)
        return ["type": "function", "function": function]
    }

    private static func responseOutput(
        message: [String: Any],
        responseID: String,
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> [[String: Any]] {
        var output: [[String: Any]] = []
        if let content = message["content"] as? String {
            output.append([
                "id": "msg_\(responseID)",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": content,
                        "annotations": [],
                        "logprobs": [],
                    ]
                ],
            ])
        } else if message["content"] is NSNull == false, message["content"] != nil {
            throw Error.invalidResponse
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for (index, call) in toolCalls.enumerated() {
                guard
                    let callID = nonemptyString(call["id"]),
                    call["type"] as? String == "function",
                    let function = call["function"] as? [String: Any],
                    let name = nonemptyString(function["name"]),
                    let arguments = function["arguments"] as? String
                else {
                    throw Error.invalidResponse
                }
                var call: [String: Any] = [
                    "id": "fc_\(responseID)_\(index)",
                    "type": "function_call",
                    "status": "completed",
                    "call_id": callID,
                    "name": name,
                    "arguments": arguments,
                ]
                if let binding = bindings[name] {
                    call["name"] = binding.name
                    call["namespace"] = binding.namespace
                }
                output.append(call)
            }
        }
        if output.isEmpty {
            output.append([
                "id": "msg_\(responseID)",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": "",
                        "annotations": [],
                        "logprobs": [],
                    ]
                ],
            ])
        }
        return output
    }

    private static func stringFragment(_ value: Any?) throws -> String? {
        if let string = value as? String {
            return string
        }
        guard let value else {
            return nil
        }
        let fragment = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(data: fragment, encoding: .utf8)
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

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}
