import Foundation

extension OpenAIResponsesChatCompletions {
    static func chatToolChoice(
        _ value: Any?,
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> Any? {
        try ResponsesToolChoice.chat(value, bindings: bindings)
    }
}
