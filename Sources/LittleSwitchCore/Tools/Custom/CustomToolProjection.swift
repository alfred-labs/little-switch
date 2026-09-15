import Foundation
import LittleSwitchWire

/// Immutable, exact identity map for a single provider exchange.
package struct CustomToolProjection: Sendable {
    package enum Error: Swift.Error, Equatable {
        case invalidRequest
        case invalidResponse
        case limitExceeded
    }

    /// Byte-exact names: Swift's canonically equivalent String equality is not
    /// an aliasing rule for wire identifiers.
    struct Identity: Hashable, Sendable {
        let name: Data
        let namespace: Data?

        init(name: String, namespace: String? = nil) {
            self.name = Data(name.utf8)
            self.namespace = namespace.map { Data($0.utf8) }
        }

        init?(_ value: JSONValue) {
            guard let name = value.object?[OpenAIResponsesFunctionCall.Key.name.rawValue]?.string, !name.isEmpty else {
                return nil
            }
            let namespace = value.object?[OpenAIResponsesFunctionCall.Key.namespace.rawValue]
            guard namespace == nil || namespace == .null || namespace?.string != nil else { return nil }
            self.init(name: name, namespace: namespace?.string)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(namespace)
        }
    }

    package let upstreamBody: Data
    package let originalBody: Data
    package let wire: ProviderToolContract.Wire
    let declarations: [Identity: JSONValue]
    let allowed: Set<Identity>
    let wireIdentities: Set<Identity>

    package var isIdentity: Bool { declarations.isEmpty }

    package static func prepare(body: Data, wire: ProviderToolContract.Wire, adapt: Bool) throws -> Self {
        guard adapt, wire != .anthropic else {
            return Self(
                upstreamBody: body, originalBody: body, wire: wire, declarations: [:], allowed: [], wireIdentities: [])
        }
        let catalog = try ProviderToolContractCatalog(wire: wire, requestBody: body)
        var request = CustomToolRequestProjection(body: body, wire: wire)
        let projected = try request.project()
        let allowed = Set(
            catalog.allowedIdentities.filter { $0.kind == .custom }.map {
                Identity(name: $0.name, namespace: $0.namespace)
            })
        return Self(
            upstreamBody: projected,
            originalBody: body,
            wire: wire,
            declarations: request.declarations,
            allowed: allowed,
            wireIdentities: Set(catalog.allowedIdentities.map { Identity(name: $0.name, namespace: $0.namespace) }))
    }

    func adapts(_ value: JSONValue) -> Bool {
        guard let identity = Identity(value) else { return false }
        return allowed.contains(identity)
    }

    func declares(_ value: JSONValue) -> Bool {
        guard let identity = Identity(value) else { return false }
        return wireIdentities.contains(identity)
    }

    package func restoreBuffered(_ body: Data) throws -> Data {
        guard !isIdentity else { return body }
        let root = try JSONValue.parse(body)
        let restored = try restore(root)
        return root == restored ? body : try restored.serializedData()
    }
}
