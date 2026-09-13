import Foundation

// The chat-completions projection assembles Responses output items from the
// provider's terminal assistant message: text becomes a `message` item and
// each tool call becomes a `function_call` item under its restored identity.

extension OpenAIResponsesChatCompletions {
    static func responseOutput(
        message: [String: Any],
        responseID: String,
        bindings: [String: ResponsesToolNamespaces.Binding],
        resolver: ProviderToolNamespaceResolver,
        providerID: UUID? = nil
    ) throws -> [[String: Any]] {
        var output: [[String: Any]] = []
        let reasoning = try ResponsesChatCompletionsReasoning.item(
            message: message, responseID: responseID, providerID: providerID)
        if let reasoning {
            output.append(reasoning)
        }
        var contentParts: [[String: Any]] = []
        if let content = message["content"] as? String {
            contentParts.append(["type": "output_text", "text": content, "annotations": [], "logprobs": []])
        } else if message["content"] is NSNull == false, message["content"] != nil {
            throw Error.invalidResponse
        }
        if let refusal = message["refusal"], !(refusal is NSNull) {
            guard let refusal = refusal as? String else { throw Error.invalidResponse }
            contentParts.append(["type": "refusal", "refusal": refusal])
        }
        if !contentParts.isEmpty {
            output.append([
                "id": "msg_\(responseID)",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": contentParts,
            ])
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for (index, call) in toolCalls.enumerated() {
                guard
                    let callID = nonemptyString(call["id"]),
                    let type = call["type"] as? String,
                    let kind = ProviderToolContractCatalog.Kind(rawValue: type),
                    let function = call[type] as? [String: Any],
                    let name = nonemptyString(function["name"]),
                    let arguments = function[kind.inputKey] as? String
                else {
                    throw Error.invalidResponse
                }
                let binding = try restoredChatToolBinding(
                    name: name, namespace: function["namespace"], bindings: bindings, resolver: resolver)
                var call: [String: Any] = [
                    "id": "\(kind.itemIDPrefix)_\(responseID)_\(index)",
                    "type": kind.responseType,
                    "status": "completed",
                    "call_id": callID,
                    "name": name,
                    kind.inputKey: arguments,
                ]
                if let binding {
                    call["name"] = binding.name
                    call["namespace"] = binding.namespace
                }
                if kind == .function {
                    call[ResponsesAgentMail.Field.encryptedFunctionArguments.rawValue] =
                        try ResponsesAgentMail.encryptedArguments(call)
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

    static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}
