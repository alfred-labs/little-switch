import Foundation

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
        guard
            let object = try JSONSerialization.jsonObject(with: body)
                as? [String: Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var rewritten = object
        var changed = false
        var droppedMailCount = 0
        var toolBindings: [String: ResponsesToolNamespaces.Binding] = [:]
        var declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:]

        if let collapsed = ResponsesHistoryDeduplication.rewritten(rewritten) {
            rewritten = collapsed
            changed = true
        }

        let history = rewritten["input"] as? [[String: Any]] ?? []
        let historicalNamespaces = history.contains { $0["namespace"] is String }
        if let tools = rewritten["tools"] as? [[String: Any]] ?? (historicalNamespaces ? [] : nil) {
            // Reassign on any namespace spec, including malformed ones that
            // flatten drops without producing bindings; forwarding those
            // as-is contradicts the rewrite.
            let containsNamespaces = tools.contains {
                $0["type"] as? String == "namespace"
            }
            if containsNamespaces || historicalNamespaces {
                let flattened = ResponsesToolNamespaces.flatten(tools: tools, history: history)
                rewritten["tools"] = flattened.tools
                toolBindings = flattened.bindings
                declaredToolBindings = flattened.declaredBindings
                changed = true
            }
        }

        if let items = rewritten["input"] as? [[String: Any]] {
            var converted: [[String: Any]] = []
            converted.reserveCapacity(items.count)
            for item in items {
                switch item["type"] as? String {
                case "web_search_call":
                    converted.append(try PortableResponsesHistory.message(for: item))
                    changed = true
                case "compaction_trigger":
                    changed = true
                case "function_call", "custom_tool_call":
                    converted.append(
                        flattenedFunctionReference(item, bindings: toolBindings, changed: &changed)
                    )
                case "agent_message":
                    // Every mail item must leave the wire: convertible ones
                    // become user messages, the rest are counted as dropped.
                    changed = true
                    if let message = mailMessageItem(item) {
                        converted.append(message)
                    } else {
                        droppedMailCount += 1
                    }
                default:
                    converted.append(item)
                }
            }
            if changed {
                rewritten["input"] = converted
            }
        }

        if let choice = rewritten["tool_choice"] {
            let flattened = try ResponsesToolChoice.normalized(choice, bindings: declaredToolBindings)
            if !NSDictionary(dictionary: ["choice": choice]).isEqual(to: ["choice": flattened]) {
                rewritten["tool_choice"] = flattened
                changed = true
            }
        }

        let toolNameCatalog = try ProviderToolContractCatalog(
            wire: .responses, requestBody: JSONSerialization.data(withJSONObject: rewritten)
        ).nameCatalog
        if try ResponsesAllowedToolSelection.apply(to: &rewritten) {
            changed = true
        }
        let customHistory = try ResponsesCustomToolHistory.normalized(rewritten, bindings: toolBindings)
        if !NSDictionary(dictionary: customHistory).isEqual(to: rewritten) {
            rewritten = customHistory
            changed = true
        }

        if let reshaped = ResponsesImageTurnCompatibility.rewritten(rewritten) {
            rewritten = reshaped
            changed = true
        }

        guard changed else {
            return Normalized(
                body: body,
                toolBindings: toolBindings,
                declaredToolBindings: declaredToolBindings,
                toolNameCatalog: toolNameCatalog,
                droppedMailCount: droppedMailCount
            )
        }
        return Normalized(
            body: try JSONSerialization.data(
                withJSONObject: rewritten,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ),
            toolBindings: toolBindings,
            declaredToolBindings: declaredToolBindings,
            toolNameCatalog: toolNameCatalog,
            droppedMailCount: droppedMailCount
        )
    }

    private static func flattenedFunctionReference(
        _ item: [String: Any],
        bindings: [String: ResponsesToolNamespaces.Binding],
        changed: inout Bool
    ) -> [String: Any] {
        guard let namespace = nonemptyResponsesString(item["namespace"]),
            let name = nonemptyResponsesString(item["name"])
        else {
            return item
        }
        var flat = item
        flat["name"] = ResponsesToolNamespaces.replayName(
            bindings: bindings,
            namespace: namespace,
            name: name
        )
        flat.removeValue(forKey: "namespace")
        changed = true
        return flat
    }

    private static func mailMessageItem(_ item: [String: Any]) -> [String: Any]? {
        guard let text = ResponsesAgentMail.textContent(item["content"]) else {
            return nil
        }
        return [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": text]],
        ]
    }
}
