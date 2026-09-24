import Foundation
import LittleSwitchWire

/// The existing declaration/selection policy consumes identities. This bounded
/// adapter keeps numeric leaves as opaque JSONValue values while strings and
/// booleans remain available to the existing policy.
enum ResponsesWireToolPolicy {
    struct Flattened {
        let tools: [JSONValue]
        let bindings: [String: ResponsesToolNamespaces.Binding]
        let declaredBindings: [String: ResponsesToolNamespaces.Binding]
    }

    static func flatten(tools: [JSONValue], history: [JSONValue]) throws -> Flattened {
        let result = ResponsesToolNamespaces.flatten(
            tools: try objects(tools), history: try objects(history))
        return try Flattened(
            tools: result.tools.map { try WireJSONCompatibility.value($0) },
            bindings: result.bindings,
            declaredBindings: result.declaredBindings)
    }

    static func choice(_ choice: JSONValue, bindings: [String: ResponsesToolNamespaces.Binding]) throws -> JSONValue {
        try WireJSONCompatibility.value(
            ResponsesToolChoice.normalized(WireJSONCompatibility.view(choice), bindings: bindings))
    }

    static func applySelection(to request: inout OpenAIResponsesRequestEnvelope) throws -> Bool {
        typealias Key = OpenAIResponsesRequestEnvelope.Key
        var policy: [String: Any] = [:]
        policy[Key.tools.rawValue] = view(request.tools)
        policy[Key.toolChoice.rawValue] = view(request.toolChoice)
        guard try ResponsesAllowedToolSelection.apply(to: &policy) else { return false }
        request.tools = try presence(policy[Key.tools.rawValue])
        request.toolChoice = try presence(policy[Key.toolChoice.rawValue])
        return true
    }

    static func nameCatalog(
        _ request: OpenAIResponsesRequestEnvelope, bindings: [String: ResponsesToolNamespaces.Binding] = [:]
    ) throws -> ProviderToolNameCatalog {
        // Catalogue construction receives identities only; unknown request and
        // schema subtrees cannot authorize a tool and are never serialized here.
        let identities = OpenAIResponsesRequestEnvelope(
            input: .value(identityProjection(request.input.value ?? .array([]))),
            toolChoice: request.toolChoice.value.map { .value(identityProjection($0)) } ?? .null,
            tools: .value(identityProjection(request.tools.value ?? .array([])))
        )
        let catalog = try ProviderToolContractCatalog(wire: .responses, requestBody: WireCodec.encode(identities))
            .nameCatalog
        let history = try objects(identities.input.value?.array ?? [])
        return ProviderToolNameCatalog(
            declared: catalog.declared,
            historical: ResponsesToolNamespaces.historicalNames(history, bindings: bindings))
    }

    private static func view(_ presence: JSONPresence<JSONValue>) -> Any? {
        switch presence {
        case .absent: nil
        case .null: NSNull()
        case .value(let value): WireJSONCompatibility.view(value)
        }
    }

    private static func presence(_ value: Any?) throws -> JSONPresence<JSONValue> {
        guard let value else { return .absent }
        if value is NSNull { return .null }
        return .value(try WireJSONCompatibility.value(value))
    }

    private static func identityProjection(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let values): return .array(values.map(identityProjection))
        case .object(let fields):
            let keys: Set<String> = ["type", "name", "namespace", "tools", "mode"]
            return .object(
                .init(
                    uniqueKeysWithValues: fields.filter { keys.contains($0.key) }.map {
                        ($0.key, identityProjection($0.value))
                    }))
        default: return value
        }
    }

    static func objects(_ values: [JSONValue]) throws -> [[String: Any]] {
        try values.map {
            guard let fields = WireJSONCompatibility.view($0) as? [String: Any] else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return fields
        }
    }

}
