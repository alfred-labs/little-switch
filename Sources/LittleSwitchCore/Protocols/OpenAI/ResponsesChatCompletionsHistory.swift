import Foundation
import LittleSwitchWire

/// Keeps a Responses assistant turn together on Chat's message-oriented wire.
/// Tool results and incoming messages delimit turns; parallel calls share one
/// assistant message with its text and provider reasoning.
enum ResponsesChatCompletionsHistory {
    static func append(
        _ input: Any,
        to messages: inout [[String: Any]],
        bindings: [String: ResponsesToolNamespaces.Binding],
        providerID: UUID? = nil
    ) throws -> Int {
        if let text = input as? String {
            messages.append(["role": "user", "content": text])
            return 0
        }
        guard let items = input as? [[String: Any]] else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        var droppedMailCount = 0
        var pendingCalls: Set<String> = []
        var pendingImages: [[String: Any]] = []
        for item in items {
            let kind = item[OpenAIResponsesUserMessage.Key.type.rawValue] as? String
            if !pendingImages.isEmpty, kind != "function_call_output", kind != "custom_tool_call_output" {
                throw OpenAIResponsesChatCompletions.Error.invalidRequest
            }
            switch kind {
            case "message":
                try appendMessage(item, to: &messages)
            case "function_call", "custom_tool_call":
                let call = try toolCall(item, bindings: bindings)
                if let id = item[OpenAIResponsesInputFunctionCall.Key.callId.rawValue] as? String {
                    pendingCalls.insert(id)
                }
                var message = takeAssistant(from: &messages)
                var calls = message["tool_calls"] as? [[String: Any]] ?? []
                calls.append(call)
                message["tool_calls"] = calls
                messages.append(message)
            case "function_call_output", "custom_tool_call_output":
                let output = try ResponsesChatCompletionsToolOutput.project(item: item)
                messages.append(output.toolMessage)
                pendingImages.append(contentsOf: output.imageMessages)
                if let callID = item["call_id"] as? String { pendingCalls.remove(callID) }
                if pendingCalls.isEmpty {
                    messages.append(contentsOf: pendingImages)
                    pendingImages.removeAll()
                }
            case "reasoning":
                if let fields = try ResponsesChatCompletionsReasoning.fields(from: item, providerID: providerID) {
                    // A carrier is one complete Chat assistant state. A
                    // preceding synthetic summary belongs to an earlier turn.
                    var message: [String: Any] = ["role": "assistant", "content": NSNull()]
                    for (key, value) in fields { message[key] = value }
                    messages.append(message)
                }
            case "compaction_trigger":
                continue
            case "agent_message":
                if let content = ResponsesAgentMail.textContent(item["content"]) {
                    messages.append(["role": "user", "content": content])
                } else {
                    droppedMailCount += 1
                }
            case "web_search_call":
                guard let message = try? PortableResponsesHistory.message(for: item) else {
                    throw OpenAIResponsesChatCompletions.Error.invalidRequest
                }
                try appendMessage(message, to: &messages)
            default:
                throw OpenAIResponsesChatCompletions.Error.invalidRequest
            }
        }
        guard pendingImages.isEmpty else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        return droppedMailCount
    }

    private static func toolCall(
        _ item: [String: Any], bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> [String: Any] {
        let kind = item["type"] as? String == "custom_tool_call" ? "custom" : "function"
        let payloadKey = kind == "custom" ? "input" : "arguments"
        guard let callID = nonemptyResponsesString(item["call_id"]),
            let name = nonemptyResponsesString(item["name"]), let payload = item[payloadKey] as? String
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        let wireName =
            nonemptyResponsesString(item["namespace"]).map {
                ResponsesToolNamespaces.replayName(bindings: bindings, namespace: $0, name: name)
            } ?? name
        return ["id": callID, "type": kind, kind: ["name": wireName, payloadKey: payload]]
    }

    private static func appendMessage(_ item: [String: Any], to messages: inout [[String: Any]]) throws {
        guard let role = nonemptyResponsesString(item["role"]) else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        let chatRole = role == "developer" ? "system" : role
        guard ["system", "user", "assistant"].contains(chatRole) else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        var message: [String: Any] = ["role": chatRole]
        if let text = item["content"] as? String {
            message["content"] = text
        } else {
            guard let parts = item["content"] as? [[String: Any]] else {
                throw OpenAIResponsesChatCompletions.Error.invalidRequest
            }
            let refusals = parts.filter { $0["type"] as? String == "refusal" }
            let content = parts.filter { $0["type"] as? String != "refusal" }
            if !refusals.isEmpty {
                let texts = refusals.compactMap { $0["refusal"] as? String }
                guard chatRole == "assistant", texts.count == refusals.count else {
                    throw OpenAIResponsesChatCompletions.Error.invalidRequest
                }
                message["refusal"] = texts.joined(separator: "\n")
            }
            message["content"] =
                content.isEmpty && !refusals.isEmpty ? NSNull() : try messageContent(content)
        }
        if chatRole == "assistant", continuesAssistant(messages.last) {
            var combined = messages.removeLast()
            combined["content"] = joinedContent(combined["content"], message["content"])
            if let refusal = message["refusal"] as? String {
                combined["refusal"] = (combined["refusal"] as? String).map { $0 + "\n" + refusal } ?? refusal
            }
            messages.append(combined)
        } else {
            messages.append(message)
        }
    }

    private static func messageContent(_ parts: [[String: Any]]) throws -> Any {
        let texts = parts.compactMap { part -> String? in
            guard ["input_text", "output_text"].contains(part["type"] as? String ?? "") else { return nil }
            return part["text"] as? String
        }
        if texts.count == parts.count { return texts.joined(separator: "\n") }
        guard let multipart = ResponsesChatCompletionsImageContent.multipart(parts) else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        return multipart
    }

    private static func takeAssistant(from messages: inout [[String: Any]]) -> [String: Any] {
        if messages.last?["role"] as? String == "assistant" { return messages.removeLast() }
        return ["role": "assistant", "content": NSNull()]
    }

    private static func continuesAssistant(_ message: [String: Any]?) -> Bool {
        guard let message, message["role"] as? String == "assistant" else { return false }
        return message["tool_calls"] != nil || message["reasoning"] != nil || message["reasoning_content"] != nil
    }

    private static func joinedContent(_ previous: Any?, _ next: Any?) -> Any? {
        if previous == nil || previous is NSNull { return next }
        if next == nil || next is NSNull { return previous }
        if let left = previous as? String, let right = next as? String {
            return left + "\n" + right
        }
        return [previous, next].compactMap(contentParts).flatMap(\.self)
    }

    private static func contentParts(_ content: Any?) -> [[String: Any]]? {
        if let text = content as? String { return [["type": "text", "text": text]] }
        return content as? [[String: Any]]
    }

}
