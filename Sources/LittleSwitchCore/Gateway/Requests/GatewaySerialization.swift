import Foundation

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
        guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw Error.invalidJSONObject
        }
        var rewritten = try PortableToolHistory.anthropic(root)
        try ProviderToolRequestPolicy.anthropic(rewritten)
        rewritten["model"] = modelID
        return try JSONSerialization.data(
            withJSONObject: rewritten,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    package func rewriteResponses(_ body: Data, modelID: String) throws -> Data {
        try rewrite(body, modelID: modelID)
    }

    private func rewrite(_ body: Data, modelID: String) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw Error.invalidJSONObject
        }
        var rewritten = root
        rewritten["model"] = modelID
        return try JSONSerialization.data(
            withJSONObject: rewritten,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private enum Error: Swift.Error {
        case invalidJSONObject
    }
}
