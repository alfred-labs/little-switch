import Foundation

extension ProviderToolContractCatalog.Kind {
    var responseType: String { self == .function ? "function_call" : "custom_tool_call" }
    var itemIDPrefix: String { self == .function ? "fc" : "ct" }
}

func restoredChatToolBinding(
    name: String,
    namespace: Any?,
    bindings: [String: ResponsesToolNamespaces.Binding],
    resolver: ProviderToolNamespaceResolver
) throws -> ResponsesToolNamespaces.Binding? {
    guard let namespace, !(namespace is NSNull) else {
        return resolver.restoredBinding(for: name, bindings: bindings)
    }
    guard let namespace = nonemptyResponsesString(namespace),
        let binding = resolver.restoredBinding(for: name, namespace: namespace, bindings: bindings)
    else { throw OpenAIResponsesChatCompletions.Error.invalidResponse }
    return binding
}
