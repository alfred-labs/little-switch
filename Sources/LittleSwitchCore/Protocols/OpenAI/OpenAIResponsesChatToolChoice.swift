import Foundation

extension OpenAIResponsesChatCompletions {
    static func chatToolChoice(
        _ value: Any?,
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) -> Any? {
        if let string = value as? String, ["auto", "none", "required"].contains(string) {
            return string
        }
        guard let object = value as? [String: Any],
            object["type"] as? String == "function",
            let name = nonemptyResponsesString(object["name"])
        else {
            return nil
        }
        let wireName: String
        if let namespace = nonemptyResponsesString(object["namespace"]) {
            wireName = ResponsesToolNamespaces.replayName(bindings: bindings, namespace: namespace, name: name)
        } else {
            wireName = name
        }
        return ["type": "function", "function": ["name": wireName]]
    }
}
