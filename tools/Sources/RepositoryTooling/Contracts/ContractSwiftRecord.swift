import Foundation

extension ContractEmitter {
    mutating func record(
        _ fields: [ContractField], additional: ContractAdditionalFields, name: String
    ) throws -> String {
        let members = fields.map { ContractSwiftNames.member($0.key) }
        try ContractSwiftNames.unique(
            members + ["additionalFields", "wireJSON", "Key"], contract: graph.rootID, pointer: name)
        var properties: [String] = []
        var parameters: [String] = []
        var assignments: [String] = []
        var decoding: [String] = []
        var encoding: [String] = []
        for (field, member) in zip(fields, members) {
            let shape = try presence(field.schema)
            let sourcePointer = try graph.resolved(field.schema).pointer
            let base = try type(
                shape.base, suggested: graph.typeNames[sourcePointer] ?? name + ContractSwiftNames.type(field.key))
            let fieldType: String
            let decode: String
            let encode: String
            let defaultValue: String
            switch (field.required, shape.nullable) {
            case (true, false):
                fieldType = base
                decode = "required"
                encode = "set"
                defaultValue = ""
            case (true, true):
                fieldType = base + "?"
                decode = "nullable"
                encode = "setNullable"
                defaultValue = ""
            case (false, false):
                fieldType = base + "?"
                decode = "optional"
                encode = "setOptional"
                defaultValue = " = nil"
            case (false, true):
                fieldType = "JSONPresence<\(base)>"
                decode = "presence"
                encode = "setPresence"
                defaultValue = " = .absent"
            }
            properties.append("    public var \(member): \(fieldType)")
            parameters.append("        \(member): \(fieldType)\(defaultValue),")
            assignments.append("        self.\(member) = \(member)")
            let argument = member.replacingOccurrences(of: "`", with: "")
            decoding.append("            \(argument): try object.\(decode)(Key.\(member).rawValue),")
            encoding.append("        try object.\(encode)(self.\(member), for: Key.\(member).rawValue)")
        }
        let extrasValidation = try validateAdditional(additional, name: name)
        let keys = zip(fields, members).map { "        " + ContractSwiftNames.enumCase($1, value: $0.key) }
            .joined(separator: "\n")
        let keyDeclaration =
            fields.isEmpty
            ? "    private enum Key { static let allCases: [String] = [] }"
            : "    \(graph.publicKeys ? "public" : "private") enum Key: String, CaseIterable, Sendable {\n\(keys)\n    }"
        let knownKeys = fields.isEmpty ? "Key.allCases" : "Key.allCases.map(\\.rawValue)"
        return """
            public struct \(name): Sendable, WireCodable {
            \(properties.joined(separator: "\n"))
                public var additionalFields: JSONObject

                public init(
            \(parameters.joined(separator: "\n"))
                    additionalFields: JSONObject = WireObject.emptyFields
                ) {
            \(assignments.joined(separator: "\n"))
                    self.additionalFields = additionalFields
                }

                public init(wireJSON: JSONValue) throws {
                    let object = try WireObject(wireJSON)
                    self.init(
            \(decoding.joined(separator: "\n"))
                        additionalFields: object.additionalFields(excluding: \(knownKeys))
                    )
            \(extrasValidation)
                }

                public func wireJSON() throws -> JSONValue {
                    \(fields.isEmpty ? "let" : "var") object = try WireObject(additionalFields: self.additionalFields, knownKeys: \(knownKeys))
            \(extrasValidation)
            \(encoding.joined(separator: "\n"))
                    return object.wireJSON
                }

            \(keyDeclaration)
            }
            """
    }

    private mutating func validateAdditional(_ additional: ContractAdditionalFields, name: String) throws -> String {
        switch additional {
        case .allowed: return ""
        case .forbidden:
            return "        guard self.additionalFields.isEmpty else { throw WireCodingError(.typeMismatch) }"
        case .typed(let pointer):
            if case .opaque = try graph.resolved(pointer).kind { return "" }
            let valueType = try type(pointer, suggested: name + "AdditionalValue")
            return "        for value in self.additionalFields.values { _ = try \(valueType)(wireJSON: value) }"
        }
    }
}
