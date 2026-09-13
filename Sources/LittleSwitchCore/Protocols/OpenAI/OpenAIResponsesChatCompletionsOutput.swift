import Foundation
import LittleSwitchWire

// The chat-completions projection assembles Responses output items from the
// provider's terminal assistant message: text becomes a `message` item and
// each tool call becomes a `function_call` item under its restored identity.

extension OpenAIResponsesChatCompletions {
    static func responseOutput(
        message: OpenAIChatMessage,
        responseID: String,
        bindings: [String: ResponsesToolNamespaces.Binding],
        resolver: ProviderToolNamespaceResolver,
        providerID: UUID? = nil
    ) throws -> [[String: Any]] {
        var output: [[String: Any]] = []
        let reasoning = try ResponsesChatCompletionsReasoning.item(
            message: ResponsesChatCompletionsReasoning.wireFields(in: message.additionalFields),
            responseID: responseID,
            providerID: providerID)
        if let reasoning {
            output.append(reasoning)
        }
        var contentParts: [OpenAIResponsesContentPart] = []
        if let content = message.content.value {
            contentParts.append(
                .outputText(
                    OpenAIResponsesOutputText(
                        annotations: .value([]), logprobs: .value([]), text: content, type: .outputText)))
        }
        if let refusal = message.refusal.value {
            contentParts.append(.refusal(OpenAIResponsesRefusal(refusal: refusal, type: .refusal)))
        }
        if !contentParts.isEmpty {
            output.append(try responseMessage(id: "msg_\(responseID)", content: contentParts))
        }

        if let toolCalls = message.toolCalls.value {
            for (index, call) in toolCalls.enumerated() {
                let input = try ChatCompletionToolInput(call)
                guard !input.callID.isEmpty, !input.name.isEmpty else {
                    throw Error.invalidResponse
                }
                let kind = input.kind
                let binding = try restoredChatToolBinding(
                    name: input.name, namespace: input.namespace, bindings: bindings, resolver: resolver)
                let itemID = "\(kind.itemIDPrefix)_\(responseID)_\(index)"
                switch kind {
                case .function:
                    var call = chatFunctionItem(
                        itemID: itemID,
                        callID: input.callID,
                        name: input.name,
                        arguments: input.arguments,
                        status: .completed,
                        binding: binding)
                    if ResponsesAgentMail.requiresPlaintext(namespace: call.namespace.value, name: call.name) {
                        call.encryptedFunctionArgs = .value([])
                    }
                    output.append(try WireJSONCompatibility.fields(call.wireJSON()))
                case .custom:
                    let call = OpenAIResponsesCustomCall(
                        callId: input.callID,
                        id: itemID,
                        input: input.arguments,
                        name: binding?.name ?? input.name,
                        namespace: binding.map { .value($0.namespace) } ?? .absent,
                        status: .value(.completed),
                        type: .customToolCall)
                    output.append(try WireJSONCompatibility.fields(call.wireJSON()))
                }
            }
        }
        if output.isEmpty {
            output.append(
                try responseMessage(
                    id: "msg_\(responseID)",
                    content: [
                        .outputText(
                            OpenAIResponsesOutputText(
                                annotations: .value([]), logprobs: .value([]), text: "", type: .outputText))
                    ]))
        }
        return output
    }

    private static func responseMessage(
        id: String,
        content: [OpenAIResponsesContentPart]
    ) throws -> [String: Any] {
        try WireJSONCompatibility.fields(
            OpenAIResponsesMessage(
                content: content, id: id, role: .assistant, status: .value(.completed), type: .message
            ).wireJSON())
    }

    static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}
