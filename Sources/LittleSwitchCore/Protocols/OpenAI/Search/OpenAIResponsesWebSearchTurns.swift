import Foundation

package struct ResponsesUsage: Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var cachedInputTokens: Int
    var cacheWriteInputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    package init(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens =
            totalTokens ?? saturatedResponsesUsageSum(inputTokens, outputTokens)
    }

    mutating func add(_ other: ResponsesUsage) {
        inputTokens = saturatedResponsesUsageSum(inputTokens, other.inputTokens)
        outputTokens = saturatedResponsesUsageSum(outputTokens, other.outputTokens)
        cachedInputTokens = saturatedResponsesUsageSum(
            cachedInputTokens,
            other.cachedInputTokens
        )
        cacheWriteInputTokens = saturatedResponsesUsageSum(
            cacheWriteInputTokens,
            other.cacheWriteInputTokens
        )
        reasoningOutputTokens = saturatedResponsesUsageSum(
            reasoningOutputTokens,
            other.reasoningOutputTokens
        )
        totalTokens = saturatedResponsesUsageSum(totalTokens, other.totalTokens)
    }
}

private func saturatedResponsesUsageSum(_ lhs: Int, _ rhs: Int) -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? Int.max : result.partialValue
}

package struct ResponsesWebSearchToolCall: Equatable, Sendable {
    let callID: String
    let query: String
    var privateToolName = "web_search"
}

package struct ResponsesModelTurn: Equatable, Sendable {
    let id: String
    let rootJSON: Data
    let outputJSON: Data
    let usage: ResponsesUsage
    let webSearchCall: ResponsesWebSearchToolCall?
}

extension OpenAIResponsesWebSearch {
    enum FollowUpMode {
        case result
        case terminalError
    }

    static func parseModelTurn(_ body: Data, privateToolName: String? = "web_search") throws -> ResponsesModelTurn {
        let object = try turnObject(from: body)
        let terminalStatus = try modelTerminalStatus(from: object)
        var output = object["output"] as? [[String: Any]]
        if terminalStatus == .failed, object["output"] == nil {
            output = []
        }
        guard let id = object["id"] as? String, !id.isEmpty,
            let output
        else {
            throw Error.invalidResponse
        }
        let usageObject: [String: Any]
        if let usage = object["usage"] as? [String: Any] {
            usageObject = usage
        } else if terminalStatus == .failed, object["usage"] == nil || object["usage"] is NSNull {
            usageObject = [:]
        } else {
            throw Error.invalidResponse
        }

        var searchCall: ResponsesWebSearchToolCall?
        for item in output {
            guard item["type"] is String else {
                throw Error.invalidResponse
            }
            // A terminal interruption can contain fully shaped tool calls.
            // Only a completed model turn may authorize another search.
            guard terminalStatus == .completed,
                let privateToolName, isPrivateSearchCall(item, privateToolName: privateToolName)
            else {
                continue
            }
            guard let callID = item["call_id"] as? String, !callID.isEmpty else {
                throw Error.invalidResponse
            }
            if searchCall == nil {
                searchCall = ResponsesWebSearchToolCall(
                    callID: callID,
                    query: searchQuery(from: item["arguments"]),
                    privateToolName: privateToolName
                )
            }
        }

        let inputTokens = try tokenCount(usageObject["input_tokens"])
        let outputTokens = try tokenCount(usageObject["output_tokens"])
        let inputDetails = try optionalTokenDetails(
            usageObject["input_tokens_details"]
        )
        let outputDetails = try optionalTokenDetails(
            usageObject["output_tokens_details"]
        )
        let cachedInputTokens = try requiredDetailTokenCount(
            inputDetails,
            key: "cached_tokens"
        )
        let cacheWriteInputTokens = try optionalDetailTokenCount(
            inputDetails,
            key: "cache_write_tokens"
        )
        let reasoningOutputTokens = try requiredDetailTokenCount(
            outputDetails,
            key: "reasoning_tokens"
        )
        let totalTokens: Int
        if usageObject["total_tokens"] == nil {
            totalTokens = saturatedResponsesUsageSum(inputTokens, outputTokens)
        } else {
            totalTokens = try tokenCount(usageObject["total_tokens"])
        }
        return ResponsesModelTurn(
            id: id,
            rootJSON: try turnData(from: object),
            outputJSON: try turnFragmentData(from: output),
            usage: ResponsesUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cachedInputTokens: cachedInputTokens,
                cacheWriteInputTokens: cacheWriteInputTokens,
                reasoningOutputTokens: reasoningOutputTokens,
                totalTokens: totalTokens
            ),
            webSearchCall: searchCall
        )
    }

    static func modelTerminalStatus(from object: [String: Any]) throws -> ResponsesStreamTerminal {
        // Legacy buffered providers may omit status; an explicit status must
        // always be a known terminal before the bridge can continue the turn.
        guard let value = object["status"] else {
            return .completed
        }
        guard let status = value as? String,
            let terminal = ResponsesStreamTerminal(rawValue: status)
        else {
            throw Error.invalidResponse
        }
        return terminal
    }

    static func followUpRequest(
        baseBody: Data,
        turn: ResponsesModelTurn,
        toolCall: ResponsesWebSearchToolCall,
        resultText: String,
        mode: FollowUpMode
    ) throws -> Data {
        var object = try turnObject(from: baseBody)
        let output = try turnOutput(from: turn.outputJSON)
        guard
            output.contains(where: { item in
                isPrivateSearchCall(item, privateToolName: toolCall.privateToolName)
                    && item["call_id"] as? String == toolCall.callID
            })
        else {
            throw Error.invalidResponse
        }

        let followUpOutput = output.filter { item in
            guard isPrivateSearchCall(item, privateToolName: toolCall.privateToolName) else {
                return true
            }
            return item["call_id"] as? String == toolCall.callID
        }
        var input = try normalizedInput(object["input"])
        input.append(contentsOf: followUpOutput)
        input.append([
            "type": "function_call_output",
            "call_id": toolCall.callID,
            "output": resultText,
        ])
        object["input"] = input

        if mode == .terminalError, let tools = object["tools"] as? [[String: Any]] {
            let remainingTools = tools.filter { !isPrivateSearchTool($0, privateToolName: toolCall.privateToolName) }
            if remainingTools.isEmpty {
                object.removeValue(forKey: "tools")
            } else {
                object["tools"] = remainingTools
            }
            object["tool_choice"] = toolChoiceWithoutSearch(
                object["tool_choice"], remainingTools: remainingTools, privateToolName: toolCall.privateToolName
            )
        }
        return try turnData(from: object)
    }

    private static func searchQuery(from arguments: Any?) -> String {
        guard let arguments = arguments as? String,
            let data = arguments.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ""
        }
        return object["query"] as? String ?? ""
    }

    private static func tokenCount(_ value: Any?) throws -> Int {
        guard let value = value as? Int, value >= 0 else {
            if value == nil {
                return 0
            }
            throw Error.invalidResponse
        }
        return value
    }

    private static func optionalTokenDetails(
        _ value: Any?
    ) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let details = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        return details
    }

    private static func requiredDetailTokenCount(
        _ details: [String: Any]?,
        key: String
    ) throws -> Int {
        guard let details else {
            return 0
        }
        guard details[key] != nil else {
            throw Error.invalidResponse
        }
        return try tokenCount(details[key])
    }

    private static func optionalDetailTokenCount(
        _ details: [String: Any]?,
        key: String
    ) throws -> Int {
        guard let details else {
            return 0
        }
        return try tokenCount(details[key])
    }

    private static func normalizedInput(_ value: Any?) throws -> [[String: Any]] {
        if let text = value as? String {
            return [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": text]],
                ]
            ]
        }
        guard let input = value as? [[String: Any]] else {
            throw Error.invalidResponse
        }
        return input
    }

    private static func turnOutput(from data: Data) throws -> [[String: Any]] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Error.invalidResponse
        }
        guard let output = value as? [[String: Any]] else {
            throw Error.invalidResponse
        }
        return output
    }

    private static func turnObject(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidResponse
        }
        guard let object = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        return object
    }

    private static func turnData(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func turnFragmentData(from value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
