import Foundation

/// Declarations reserve names; an allowed-tools selection separately limits
/// which exact identities may appear in this model turn.
enum ProviderToolAllowedSelection {
    static func identities(
        in request: [String: Any],
        wire: ProviderToolContract.Wire,
        declared: Set<ProviderToolContractCatalog.Identity>
    ) throws -> Set<ProviderToolContractCatalog.Identity>? {
        guard wire != .anthropic,
            let choice = request["tool_choice"] as? [String: Any],
            choice["type"] as? String == "allowed_tools"
        else { return nil }
        let selection: [String: Any]
        if wire == .chatCompletions {
            guard let nested = choice["allowed_tools"] as? [String: Any] else {
                throw ProviderToolContract.Error.invalidRequest
            }
            selection = nested
        } else {
            selection = choice
        }
        guard let mode = selection["mode"] as? String, ["auto", "required"].contains(mode),
            let references = selection["tools"] as? [[String: Any]]
        else { throw ProviderToolContract.Error.invalidRequest }
        let allowed = try Set(references.map { try identity($0, wire: wire) })
        guard allowed.isSubset(of: declared), mode != "required" || !allowed.isEmpty else {
            throw ProviderToolContract.Error.invalidRequest
        }
        return allowed
    }

    private static func identity(
        _ reference: [String: Any], wire: ProviderToolContract.Wire
    ) throws -> ProviderToolContractCatalog.Identity {
        guard let type = reference["type"] as? String,
            let kind = ProviderToolContractCatalog.Kind(rawValue: type)
        else { throw ProviderToolContract.Error.invalidRequest }
        let fields: [String: Any]
        if wire == .chatCompletions {
            guard let nested = reference[type] as? [String: Any] else {
                throw ProviderToolContract.Error.invalidRequest
            }
            fields = nested
        } else {
            fields = reference
        }
        guard let name = fields["name"] as? String, !name.isEmpty else {
            throw ProviderToolContract.Error.invalidRequest
        }
        let namespace: String?
        if let value = fields["namespace"], !(value is NSNull) {
            guard let string = value as? String, !string.isEmpty else {
                throw ProviderToolContract.Error.invalidRequest
            }
            namespace = string
        } else {
            namespace = nil
        }
        return .init(name: name, namespace: namespace, kind: kind)
    }
}
