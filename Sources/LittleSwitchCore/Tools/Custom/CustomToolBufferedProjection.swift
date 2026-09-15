import LittleSwitchWire

private typealias ResponseKey = OpenAIResponsesResponse.Key
private typealias FunctionKey = OpenAIResponsesFunctionCall.Key
private typealias CustomKey = OpenAIResponsesCustomCall.Key
private typealias ChatCompletionKey = CustomToolChatContract.CompletionKey
private typealias ChatChoiceKey = CustomToolChatContract.ChoiceKey
private typealias MessageKey = CustomToolChatContract.MessageKey
private typealias ChatCallKey = CustomToolChatContract.CallKey
private typealias ChatPayloadKey = CustomToolChatContract.PayloadKey

extension CustomToolProjection {
    func restore(_ value: JSONValue) throws -> JSONValue {
        guard var root = value.object else { throw Error.invalidResponse }
        switch wire {
        case .responses:
            if let output = root[ResponseKey.output.rawValue]?.array {
                root[ResponseKey.output.rawValue] = .array(try output.map { try restoreResponseItem($0) })
            }
        case .chatCompletions:
            if let choices = root[ChatCompletionKey.choices.rawValue]?.array {
                root[ChatCompletionKey.choices.rawValue] = .array(
                    try choices.map { choice in
                        guard var fields = choice.object else { throw Error.invalidResponse }
                        let message = fields[ChatChoiceKey.message.rawValue]
                        if var message = message?.object, let calls = message[MessageKey.toolCalls.rawValue]?.array {
                            message[MessageKey.toolCalls.rawValue] = .array(
                                try calls.map { try restoreChatCall($0) })
                            fields[ChatChoiceKey.message.rawValue] = .object(message)
                        }
                        return .object(fields)
                    })
            }
        case .anthropic: break
        }
        return wire == .responses ? try restoreResponseMetadata(.object(root)) : .object(root)
    }

    func restoreResponseItem(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object,
            fields[FunctionKey.type.rawValue] == .string(OpenAIResponsesFunctionCallType.functionCall.rawValue),
            adapts(value)
        else {
            return value
        }
        guard let arguments = fields.removeValue(forKey: FunctionKey.arguments.rawValue)?.string,
            fields[CustomKey.input.rawValue] == nil
        else {
            throw Error.invalidResponse
        }
        fields[CustomKey.input.rawValue] = .string(try CustomToolInputEnvelope.decode(arguments))
        fields[CustomKey.type.rawValue] = .string(OpenAIResponsesCustomCallType.customToolCall.rawValue)
        return .object(fields)
    }

    func restoreChatCall(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object,
            fields[ChatCallKey.type.rawValue] == .string(OpenAIChatFunctionCallType.function.rawValue),
            let function = fields[ChatCallKey.function.rawValue], adapts(function)
        else { return value }
        guard var payload = function.object,
            let arguments = payload.removeValue(forKey: ChatPayloadKey.arguments.rawValue)?.string,
            payload[ChatPayloadKey.input.rawValue] == nil, fields[ChatCallKey.custom.rawValue] == nil
        else { throw Error.invalidResponse }
        payload[ChatPayloadKey.input.rawValue] = .string(try CustomToolInputEnvelope.decode(arguments))
        fields.removeValue(forKey: ChatCallKey.function.rawValue)
        fields[ChatCallKey.custom.rawValue] = .object(payload)
        fields[ChatCallKey.type.rawValue] = .string(OpenAIChatCustomCallType.custom.rawValue)
        return .object(fields)
    }
}
