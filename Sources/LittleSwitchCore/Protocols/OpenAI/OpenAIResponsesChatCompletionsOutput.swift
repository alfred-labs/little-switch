import Foundation

// The chat-completions projection assembles Responses output items from the
// provider's terminal assistant message: text becomes a `message` item and
// each tool call becomes a `function_call` item under its restored identity.

extension OpenAIResponsesChatCompletions {
    static func responseOutput(
        message: [String: Any],
        responseID: String,
        bindings: [String: ResponsesToolNamespaces.Binding],
        resolver: ProviderToolNamespaceResolver?
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
                if let binding = restoredBinding(for: name, bindings: bindings, resolver: resolver) {
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

    /// The binding for an emitted call name: the exact wire name first, then
    /// a resolved near-miss among the request's own declared children.
    static func restoredBinding(
        for name: String,
        bindings: [String: ResponsesToolNamespaces.Binding],
        resolver: ProviderToolNamespaceResolver?
    ) -> ResponsesToolNamespaces.Binding? {
        if let binding = bindings[name] {
            return binding
        }
        guard let resolver, let wireName = resolver.wireName(for: name, namespace: nil) else {
            return nil
        }
        return bindings[wireName]
    }

    static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}
