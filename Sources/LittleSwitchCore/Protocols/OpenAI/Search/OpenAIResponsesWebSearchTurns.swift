import Foundation
import LittleSwitchWire

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
        let response = try responsesWireDecode(OpenAIResponsesResponse.self, from: body)
        let terminalStatus = try responsesWireTerminal(response.status)
        guard !response.id.isEmpty,
            let output = response.output ?? (terminalStatus == .failed ? [] : nil)
        else {
            throw Error.invalidResponse
        }
        guard response.usage.value != nil || terminalStatus == .failed else {
            throw Error.invalidResponse
        }
        var searchCall: ResponsesWebSearchToolCall?
        for json in output {
            let item = try responsesWireDecode(OpenAIResponsesOutputItem.self, json: json)
            // A terminal interruption can contain fully shaped tool calls.
            // Only a completed model turn may authorize another search.
            guard terminalStatus == .completed,
                let privateToolName,
                case .functionCall(let call) = item,
                call.name == privateToolName, call.namespace.value == nil
            else {
                continue
            }
            guard !call.callId.isEmpty else {
                throw Error.invalidResponse
            }
            if searchCall == nil {
                searchCall = ResponsesWebSearchToolCall(
                    callID: call.callId,
                    query: searchQuery(from: call.arguments),
                    privateToolName: privateToolName
                )
            }
        }
        return ResponsesModelTurn(
            id: response.id,
            rootJSON: body,
            outputJSON: try JSONValue.array(output).serializedData(),
            usage: try responsesWireUsage(response.usage.value),
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

    private static func searchQuery(from arguments: String) -> String {
        // The private search function's argument is owned by Core, not an SDK
        // record. Read its sole string leaf while ignoring opaque extra values.
        (try? WireObject(JSONValue.parse(Data(arguments.utf8))).required("query")) ?? ""
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
            value = WireJSONCompatibility.view(try responsesWireDecode(JSONValue.self, from: data))
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
            value = WireJSONCompatibility.view(try responsesWireDecode(JSONValue.self, from: data))
        } catch {
            throw Error.invalidResponse
        }
        guard let object = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        return object
    }

    private static func turnData(from object: [String: Any]) throws -> Data {
        try responsesStreamData(object)
    }

}
