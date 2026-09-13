import Foundation
import LittleSwitchWire

/// Rewrites Responses requests for providers reached natively.
///
/// Native providers reject or ignore the two Codex collaboration shapes:
/// `{"type": "namespace"}` tool specs hide their tools, and `agent_message`
/// input items fail with a 400 (verified against a native v1 Responses
/// provider). Normalization flattens the specs, flattens replayed
/// `function_call` names, converts mail into plain user messages, and lowers
/// allowed-tool selections to explicit declaration subsets. Bodies requiring
/// no adaptation are returned byte-identical. Mail that carries
/// no readable text cannot be converted; it is dropped from the wire and
/// counted so the gateway can record it.
package enum OpenAIResponsesNativeNamespacing {
    package struct Normalized {
        package let body: Data
        package let toolBindings: [String: ResponsesToolNamespaces.Binding]
        /// The bindings the request's own namespace declarations created —
        /// the set an emitted call may be resolved against when a provider
        /// near-misses the exact flattened name.
        package let declaredToolBindings: [String: ResponsesToolNamespaces.Binding]
        /// Includes declarations removed by a selection so an excluded plain
        /// name cannot be reinterpreted as a permitted namespace alias.
        package let toolNameCatalog: ProviderToolNameCatalog
        package let droppedMailCount: Int
    }

    package static func normalize(_ body: Data) throws -> Normalized {
        let document = try responsesWireDocument(OpenAIResponsesRequestEnvelope.self, from: body)
        var rewritten = document.value
        var changed = false
        var droppedMailCount = 0
        var toolBindings: [String: ResponsesToolNamespaces.Binding] = [:]
        var declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:]

        if let input = objectArray(rewritten.input.value) {
            let collapsed = try ResponsesHistoryDeduplication.collapsed(input)
            if collapsed.count != input.count {
                rewritten.input = .value(.array(collapsed))
                changed = true
            }
        }
        let history = objectArray(rewritten.input.value) ?? []
        let historicalNamespaces = history.contains { $0.object?["namespace"]?.string != nil }
        if let tools = objectArray(rewritten.tools.value) ?? (historicalNamespaces ? [] : nil) {
            let containsNamespaces = tools.contains { $0.object?["type"]?.string == "namespace" }
            if containsNamespaces || historicalNamespaces {
                let flattened = try ResponsesWireToolPolicy.flatten(tools: tools, history: history)
                rewritten.tools = .value(.array(flattened.tools))
                toolBindings = flattened.bindings
                declaredToolBindings = flattened.declaredBindings
                changed = true
            }
        }
        if let items = objectArray(rewritten.input.value) {
            var converted: [JSONValue] = []
            converted.reserveCapacity(items.count)
            for item in items {
                switch item.object?["type"]?.string {
                case OpenAIResponsesWebSearchCallType.webSearchCall.rawValue:
                    converted.append(try PortableResponsesHistory.message(for: item))
                    changed = true
                case "compaction_trigger":
                    changed = true
                case let type?
                where [
                    OpenAIResponsesInputFunctionCallType.functionCall.rawValue,
                    OpenAIResponsesInputCustomCallType.customToolCall.rawValue,
                ].contains(type):
                    let kind: ProviderToolContractCatalog.Kind =
                        type == OpenAIResponsesInputCustomCallType.customToolCall.rawValue ? .custom : .function
                    let flattened = try flattenedFunctionReference(item, kind: kind, bindings: toolBindings)
                    converted.append(flattened)
                    changed = changed || flattened != item
                case OpenAICodexAgentMessageType.agentMessage.rawValue:
                    changed = true
                    if let message = try mailMessageItem(item) {
                        converted.append(message)
                    } else {
                        droppedMailCount += 1
                    }
                default:
                    converted.append(item)
                }
            }
            if changed { rewritten.input = .value(.array(converted)) }
        }
        if let choice = rewritten.toolChoice.value {
            let flattened = try ResponsesWireToolPolicy.choice(choice, bindings: declaredToolBindings)
            if flattened != choice {
                rewritten.toolChoice = flattened == .null ? .null : .value(flattened)
                changed = true
            }
        }
        let toolNameCatalog = try ResponsesWireToolPolicy.nameCatalog(rewritten)
        if try ResponsesWireToolPolicy.applySelection(to: &rewritten) { changed = true }
        let customHistory = try ResponsesCustomToolHistory.normalized(rewritten, bindings: toolBindings)
        if try customHistory.wireJSON() != rewritten.wireJSON() {
            rewritten = customHistory
            changed = true
        }
        var finalJSON = try rewritten.wireJSON()
        let fields = try WireObject(finalJSON).additionalFields(excluding: [])
        if let reshaped = try ResponsesImageTurnCompatibility.rewritten(wire: fields) {
            finalJSON = responsesWireJSON(reshaped)
            changed = true
        }
        return Normalized(
            body: changed ? try finalJSON.serializedData() : document.originalData,
            toolBindings: toolBindings,
            declaredToolBindings: declaredToolBindings,
            toolNameCatalog: toolNameCatalog,
            droppedMailCount: droppedMailCount
        )
    }

    private static func objectArray(_ value: JSONValue?) -> [JSONValue]? {
        guard let values = value?.array, values.allSatisfy({ $0.object != nil }) else { return nil }
        return values
    }

    private static func flattenedFunctionReference(
        _ item: JSONValue,
        kind: ProviderToolContractCatalog.Kind,
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> JSONValue {
        switch kind {
        case .function:
            typealias Key = OpenAIResponsesInputFunctionCall.Key
            guard let namespace = nonemptyResponsesString(item.object?[Key.namespace.rawValue]),
                let name = nonemptyResponsesString(item.object?[Key.name.rawValue])
            else { return item }
            var function = try responsesWireDecode(OpenAIResponsesInputFunctionCall.self, json: item)
            function.name = ResponsesToolNamespaces.replayName(bindings: bindings, namespace: namespace, name: name)
            function.namespace = .absent
            return try function.wireJSON()
        case .custom:
            typealias Key = OpenAIResponsesInputCustomCall.Key
            guard let namespace = nonemptyResponsesString(item.object?[Key.namespace.rawValue]),
                let name = nonemptyResponsesString(item.object?[Key.name.rawValue])
            else { return item }
            var custom = try responsesWireDecode(OpenAIResponsesInputCustomCall.self, json: item)
            custom.name = ResponsesToolNamespaces.replayName(bindings: bindings, namespace: namespace, name: name)
            custom.namespace = .absent
            return try custom.wireJSON()
        }
    }

    private static func mailMessageItem(_ item: JSONValue) throws -> JSONValue? {
        let mail = try responsesWireDecode(OpenAICodexAgentMessage.self, json: item)
        guard let content = mail.content.value,
            let text = ResponsesAgentMail.textContent(WireJSONCompatibility.view(content))
        else { return nil }
        let part = OpenAIResponsesInputTextPart(text: text, type: .inputText)
        return try OpenAIResponsesUserMessage(
            content: .variant2([part.wireJSON()]), role: .user, type: .message
        ).wireJSON()
    }

}
