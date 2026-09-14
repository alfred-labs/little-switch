import Foundation
import LittleSwitchCommon
import LittleSwitchWire

package protocol GatewaySerializing: Sendable {
    func encodeJSONObject(_ object: Any) throws -> Data
    func encodeCatalog(_ response: ClaudeCatalogResponse) throws -> Data
    func rewriteMessage(_ body: Data, modelID: String) throws -> Data
    func rewriteResponses(_ body: Data, modelID: String) throws -> Data
}

package struct LiveGatewaySerializer: GatewaySerializing {
    package init() {}

    package func encodeJSONObject(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    package func encodeCatalog(_ response: ClaudeCatalogResponse) throws -> Data {
        try ClaudeCatalog.encode(response)
    }

    package func rewriteMessage(_ body: Data, modelID: String) throws -> Data {
        let root = try WireObject(WireCodec.decode(JSONValue.self, from: body).value)
        let rewritten = try PortableToolHistory.anthropic(root.additionalFields(excluding: []))
        try ProviderToolRequestPolicy.anthropic(rewritten)
        let request = AnthropicRoutingRequest(
            model: modelID,
            additionalFields: rewritten.filter { $0.key != AnthropicRoutingRequest.Key.model.rawValue })
        return try WireCodec.encode(request)
    }

    package func rewriteResponses(_ body: Data, modelID: String) throws -> Data {
        let document = try WireCodec.decode(JSONValue.self, from: body)
        let object = try WireObject(document.value)
        // Routing owns the model even when the incoming field is absent or malformed.
        let rewritten = OpenAIResponsesRoutingRequest(
            model: modelID,
            additionalFields: object.additionalFields(excluding: [OpenAIResponsesRoutingRequest.Key.model.rawValue])
        )
        return try WireCodec.encode(rewritten)
    }

}
