import Foundation
import LittleSwitchWire

/// A retired freeform tool remains useful context on function-only providers.
/// Only the outgoing copy changes: live custom declarations and the durable
/// original transcript keep their canonical custom-tool representation.
package enum ResponsesCustomToolHistory {
    package enum Error: Swift.Error, Equatable { case invalidHistory }

    /// The function-only fallback owns this single freeform argument.
    private struct RetiredCustomInput: Encodable {
        // periphery:ignore - Encodable emits this owned fallback argument as JSON.
        let input: String
    }

    private struct Identity: Hashable {
        let namespace: String?
        let name: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(namespace)
            hasher.combine(name)
        }
    }

    package static func normalized(
        _ root: [String: Any],
        bindings: [String: ResponsesToolNamespaces.Binding] = [:]
    ) throws -> [String: Any] {
        guard let input = root["input"] as? [[String: Any]] else { return root }
        let active = activeCustomTools(root["tools"] as? [[String: Any]] ?? [], bindings: bindings)
        var activeCallIDs: Set<String> = []
        var converted = input
        var changed = false
        for (index, item) in input.enumerated() where item["type"] as? String == "custom_tool_call" {
            guard let callID = nonemptyResponsesString(item["call_id"]),
                let name = nonemptyResponsesString(item["name"]), let payload = item["input"] as? String
            else { throw Error.invalidHistory }
            let identity = identity(
                namespace: nonemptyResponsesString(item["namespace"]), name: name, bindings: bindings
            )
            if active.contains(identity) {
                activeCallIDs.insert(callID)
                continue
            }
            var replacement = item
            let data = try responsesStreamData(["input": payload])
            // JSONSerialization always emits UTF-8.
            // swiftlint:disable:next optional_data_string_conversion
            replacement["arguments"] = String(decoding: data, as: UTF8.self)
            replacement.removeValue(forKey: "input")
            replacement["type"] = "function_call"
            converted[index] = replacement
            changed = true
        }
        for (index, item) in input.enumerated() where item["type"] as? String == "custom_tool_call_output" {
            guard let callID = nonemptyResponsesString(item["call_id"]), item["output"] != nil else {
                throw Error.invalidHistory
            }
            guard !activeCallIDs.contains(callID) else { continue }
            converted[index]["type"] = "function_call_output"
            changed = true
        }
        guard changed else { return root }
        var rewritten = root
        rewritten["input"] = converted
        return rewritten
    }

    private static func activeCustomTools(
        _ tools: [[String: Any]], bindings: [String: ResponsesToolNamespaces.Binding]
    ) -> Set<Identity> {
        var identities: Set<Identity> = []
        for tool in tools {
            guard let name = nonemptyResponsesString(tool["name"]) else { continue }
            if tool["type"] as? String == "custom" {
                identities.insert(identity(namespace: nil, name: name, bindings: bindings))
            } else if tool["type"] as? String == "namespace", let children = tool["tools"] as? [[String: Any]] {
                for child in children where child["type"] as? String == "custom" {
                    if let childName = nonemptyResponsesString(child["name"]) {
                        identities.insert(Identity(namespace: name, name: childName))
                    }
                }
            }
        }
        return identities
    }

    private static func identity(
        namespace: String?, name: String, bindings: [String: ResponsesToolNamespaces.Binding]
    ) -> Identity {
        // Internal search turns retain flattened declarations while projected
        // output restores the original namespace. Compare their same identity.
        guard namespace == nil, let binding = bindings[name] else {
            return Identity(namespace: namespace, name: name)
        }
        return Identity(namespace: binding.namespace, name: binding.name)
    }

    static func normalized(
        _ root: OpenAIResponsesRequestEnvelope, bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> OpenAIResponsesRequestEnvelope {
        guard let input = root.input.value?.array, input.allSatisfy({ $0.object != nil }) else { return root }
        let tools = try ResponsesWireToolPolicy.objects(root.tools.value?.array ?? [])
        let active = activeCustomTools(tools, bindings: bindings)
        var activeCallIDs: Set<String> = []
        var converted = input
        for (index, json) in input.enumerated() {
            guard
                json.object?[OpenAIResponsesInputCustomCall.Key.type.rawValue]?.string
                    == OpenAIResponsesInputCustomCallType.customToolCall.rawValue
            else { continue }
            let call: OpenAIResponsesInputCustomCall
            do { call = try OpenAIResponsesInputCustomCall(wireJSON: json) } catch { throw Error.invalidHistory }
            guard !call.callId.isEmpty, !call.name.isEmpty else { throw Error.invalidHistory }
            let namespace = call.namespace.value.flatMap { $0.isEmpty ? nil : $0 }
            let identity = identity(namespace: namespace, name: call.name, bindings: bindings)
            if active.contains(identity) {
                activeCallIDs.insert(call.callId)
                continue
            }
            // The complete freeform input becomes a string value, never parsed JSON.
            // swiftlint:disable:next optional_data_string_conversion
            let arguments = String(
                decoding: try JSONEncoder().encode(RetiredCustomInput(input: call.input)), as: UTF8.self)
            converted[index] = try OpenAIResponsesInputFunctionCall(
                arguments: arguments,
                callId: call.callId,
                id: call.id,
                name: call.name,
                namespace: call.namespace,
                type: .functionCall,
                additionalFields: call.additionalFields
            ).wireJSON()
        }
        for (index, json) in input.enumerated() {
            guard
                json.object?[OpenAIResponsesInputCustomOutput.Key.type.rawValue]?.string
                    == OpenAIResponsesInputCustomOutputType.customToolCallOutput.rawValue
            else { continue }
            let output: OpenAIResponsesInputCustomOutput
            do { output = try OpenAIResponsesInputCustomOutput(wireJSON: json) } catch { throw Error.invalidHistory }
            guard !output.callId.isEmpty else { throw Error.invalidHistory }
            guard !activeCallIDs.contains(output.callId) else { continue }
            converted[index] = try OpenAIResponsesInputFunctionOutput(
                callId: .value(output.callId),
                id: output.id.map { .value($0) } ?? .absent,
                output: output.output,
                type: .functionCallOutput,
                additionalFields: output.additionalFields
            ).wireJSON()
        }
        guard converted != input else { return root }
        var result = root
        result.input = .value(.array(converted))
        return result
    }
}
