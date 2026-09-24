import Foundation
import LittleSwitchWire

/// Removed freeform tools are context, not examples of callable functions.
/// Projection only changes the outgoing copy, retaining each complete source
/// item and its call ID. Current custom tools keep their canonical representation.
package enum ResponsesCustomToolHistory {
    package enum Error: Swift.Error, Equatable { case invalidHistory }
    private typealias Identity = CustomToolProjection.Identity
    private typealias Key = CustomToolDeclarationContract.Key
    private typealias Kind = CustomToolDeclarationContract.Kind

    package struct Projection<Request> {
        package let request: Request
        package let archivedNames: Set<String>
    }

    package static func normalized(
        _ root: [String: Any],
        bindings: [String: ResponsesToolNamespaces.Binding] = [:]
    ) throws -> Projection<[String: Any]> {
        let document = try OpenAIResponsesRequestEnvelope(wireJSON: WireJSONCompatibility.value(root))
        let projection = try normalized(document, bindings: bindings)
        return try Projection(
            request: WireJSONCompatibility.fields(projection.request.wireJSON()),
            archivedNames: projection.archivedNames)
    }

    static func normalized(
        _ root: OpenAIResponsesRequestEnvelope, bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> Projection<OpenAIResponsesRequestEnvelope> {
        guard let input = root.input.value?.array, input.allSatisfy({ $0.object != nil }) else {
            return Projection(request: root, archivedNames: [])
        }
        let tools = try ResponsesWireToolPolicy.objects(root.tools.value?.array ?? [])
        let active = activeCustomTools(tools, bindings: bindings)
        var calls: [Data: ProviderToolContractCatalog.Kind] = [:]
        var activeCallIDs: Set<Data> = []
        var archivedNames: Set<String> = []
        var converted = input

        for (index, item) in input.enumerated() {
            switch item.object?[OpenAIResponsesInputCustomCall.Key.type.rawValue]?.string {
            case OpenAIResponsesInputCustomCallType.customToolCall.rawValue:
                let call: OpenAIResponsesInputCustomCall
                do { call = try OpenAIResponsesInputCustomCall(wireJSON: item) } catch { throw Error.invalidHistory }
                guard !call.callId.isEmpty, !call.name.isEmpty else { throw Error.invalidHistory }
                let id = Data(call.callId.utf8)
                guard calls.updateValue(.custom, forKey: id) == nil else { throw Error.invalidHistory }
                let identity = identity(namespace: call.namespace.value, name: call.name, bindings: bindings)
                if active.contains(identity) {
                    activeCallIDs.insert(id)
                } else {
                    archivedNames.insert(call.name)
                    converted[index] = try ResponsesRetiredToolMessage.project(item)
                }
            case OpenAIResponsesInputFunctionCallType.functionCall.rawValue:
                if let id = item.object?[OpenAIResponsesInputFunctionCall.Key.callId.rawValue]?.string {
                    guard calls.updateValue(.function, forKey: Data(id.utf8)) != .custom else {
                        throw Error.invalidHistory
                    }
                }
            default: continue
            }
        }

        try projectOutputs(input, calls: calls, activeCallIDs: activeCallIDs, into: &converted)
        var result = root
        if converted != input { result.input = .value(.array(converted)) }
        return Projection(request: result, archivedNames: archivedNames)
    }

    private static func projectOutputs(
        _ input: [JSONValue],
        calls: [Data: ProviderToolContractCatalog.Kind],
        activeCallIDs: Set<Data>,
        into converted: inout [JSONValue]
    ) throws {
        var outputKinds: [Data: ProviderToolContractCatalog.Kind] = [:]
        for (index, item) in input.enumerated() {
            switch item.object?[OpenAIResponsesInputCustomOutput.Key.type.rawValue]?.string {
            case OpenAIResponsesInputCustomOutputType.customToolCallOutput.rawValue:
                let output: OpenAIResponsesInputCustomOutput
                do { output = try OpenAIResponsesInputCustomOutput(wireJSON: item) } catch {
                    throw Error.invalidHistory
                }
                let id = Data(output.callId.utf8)
                guard !id.isEmpty, calls[id] != .function, outputKinds.updateValue(.custom, forKey: id) == nil else {
                    throw Error.invalidHistory
                }
                if !activeCallIDs.contains(id) {
                    // An orphan result is still readable context. Never invent
                    // a matching call or infer permission from its optional name.
                    converted[index] = try ResponsesRetiredToolMessage.project(item)
                }
            case OpenAIResponsesInputFunctionOutputType.functionCallOutput.rawValue:
                if let id = item.object?[OpenAIResponsesInputFunctionOutput.Key.callId.rawValue]?.string {
                    let key = Data(id.utf8)
                    guard calls[key] != .custom, outputKinds.updateValue(.function, forKey: key) != .custom else {
                        throw Error.invalidHistory
                    }
                }
            default: continue
            }
        }
    }

    /// Chat selection has already removed excluded declarations. Retain the
    /// corresponding canonical custom specs solely for classifying history.
    static func normalizedForChat(
        _ root: [String: Any],
        tools: [[String: Any]],
        selectedTools: [[String: Any]],
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> Projection<[String: Any]> {
        let selected = Set(
            selectedTools.compactMap {
                ($0[Key.custom.rawValue] as? [String: Any])?[Key.name.rawValue] as? String
            })
        var history = root
        history[OpenAIResponsesRequestEnvelope.Key.tools.rawValue] = tools.filter {
            $0[Key.type.rawValue] as? String == Kind.custom.rawValue
                && ($0[Key.name.rawValue] as? String).map(selected.contains) == true
        }
        do { return try normalized(history, bindings: bindings) } catch {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
    }

    private static func activeCustomTools(
        _ tools: [[String: Any]], bindings: [String: ResponsesToolNamespaces.Binding]
    ) -> Set<Identity> {
        var identities: Set<Identity> = []
        for tool in tools {
            guard let name = nonemptyResponsesString(tool[Key.name.rawValue]) else { continue }
            let kind = tool[Key.type.rawValue] as? String
            if kind == Kind.custom.rawValue {
                identities.insert(identity(namespace: nil, name: name, bindings: bindings))
            } else if kind == Kind.namespace.rawValue, let children = tool[Key.tools.rawValue] as? [[String: Any]] {
                for child in children
                where child[Key.type.rawValue] as? String == Kind.custom.rawValue {
                    if let childName = nonemptyResponsesString(child[Key.name.rawValue]) {
                        identities.insert(Identity(name: childName, namespace: name))
                    }
                }
            }
        }
        return identities
    }

    private static func identity(
        namespace: String?, name: String, bindings: [String: ResponsesToolNamespaces.Binding]
    ) -> Identity {
        // An internal search turn can already use a flattened declaration.
        // Swift canonical equivalence is not equality of wire identifiers.
        guard namespace == nil, let binding = bindings.first(where: { $0.key.utf8.elementsEqual(name.utf8) })?.value
        else { return Identity(name: name, namespace: namespace) }
        return Identity(name: binding.name, namespace: binding.namespace)
    }
}
