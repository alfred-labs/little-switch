import LittleSwitchWire

/// A common input for the authorized function/custom projection in Core.
struct ChatCompletionToolInput {
    let kind: ProviderToolContractCatalog.Kind
    let callID: String
    let name: String
    let namespace: String?
    let arguments: String

    init(_ call: OpenAIChatMessageToolCall) throws {
        switch call {
        case .function(let call):
            kind = .function
            callID = call.id
            name = call.function.name
            namespace = call.function.namespace.value
            arguments = call.function.arguments
        case .custom(let call):
            kind = .custom
            callID = call.id
            name = call.custom.name
            namespace = call.custom.namespace.value
            arguments = call.custom.input
        case .unknown:
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
    }
}
