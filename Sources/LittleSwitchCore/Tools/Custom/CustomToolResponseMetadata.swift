import LittleSwitchWire

private typealias RequestKey = OpenAIResponsesRequestEnvelope.Key
private typealias Key = CustomToolDeclarationContract.Key
private typealias Kind = CustomToolDeclarationContract.Kind

extension CustomToolProjection {
    /// Responses echoes declarations and selections in created/completed
    /// snapshots too. Restore those from the manifest, not from the lossy
    /// function description that carried the grammar as instructions.
    func restoreResponseMetadata(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object else { throw Error.invalidResponse }
        if let tools = fields[RequestKey.tools.rawValue]?.array {
            fields[RequestKey.tools.rawValue] = .array(try tools.map { try restoreDeclaration($0) })
        }
        if let choice = fields[RequestKey.toolChoice.rawValue] {
            fields[RequestKey.toolChoice.rawValue] = try restoreSelection(choice)
        }
        return .object(fields)
    }

    private func restoreDeclaration(_ value: JSONValue, namespace: String? = nil) throws -> JSONValue {
        guard var fields = value.object else { throw Error.invalidResponse }
        if fields[Key.type.rawValue] == .string(Kind.namespace.rawValue) {
            guard let name = fields[Key.name.rawValue]?.string,
                let children = fields[Key.tools.rawValue]?.array
            else {
                throw Error.invalidResponse
            }
            fields[Key.tools.rawValue] = .array(
                try children.map { try restoreDeclaration($0, namespace: name) })
            return .object(fields)
        }
        guard fields[Key.type.rawValue] == .string(Kind.function.rawValue),
            let name = fields[Key.name.rawValue]?.string,
            let original = declarations[
                Identity(name: name, namespace: namespace ?? fields[Key.namespace.rawValue]?.string)]
        else { return value }
        return original
    }

    private func restoreSelection(_ value: JSONValue) throws -> JSONValue {
        guard var fields = value.object else { return value }
        let kind = fields[Key.type.rawValue]
        if kind == .string(Kind.function.rawValue), let identity = Identity(value), declarations[identity] != nil {
            fields[Key.type.rawValue] = .string(Kind.custom.rawValue)
        } else if kind == .string(Kind.allowedTools.rawValue), let tools = fields[Key.tools.rawValue]?.array {
            fields[Key.tools.rawValue] = .array(try tools.map { try restoreSelection($0) })
        }
        return .object(fields)
    }
}
