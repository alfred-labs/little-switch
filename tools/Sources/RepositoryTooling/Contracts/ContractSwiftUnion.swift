import Foundation

extension ContractEmitter {
    mutating func union(_ kind: ContractUnionKind, branches: [String], name: String, pointer: String) throws -> String {
        let tag = try discriminator(branches, pointer: pointer)
        var cases: [String] = []
        var types: [String] = []
        for (index, branch) in branches.enumerated() {
            let member = tag.map { ContractSwiftNames.member($0.values[index]) } ?? "variant\(index + 1)"
            cases.append(member)
            types.append(try type(branch, suggested: name + ContractSwiftNames.type(member)))
        }
        try ContractSwiftNames.unique(cases + ["unknown"], contract: graph.rootID, pointer: pointer)
        let declarations = zip(cases, types).map { "    case \($0)(\($1))" }.joined(separator: "\n")
        let encodings = cases.map { "        case .\($0)(let value): return try Self.encode(value)" }.joined(
            separator: "\n")
        let unknownDeclaration = tag == nil ? "" : "\n    case unknown(type: String, payload: JSONValue)"
        let decoding: String
        let unknownEncoding: String
        if let tag {
            let branches = zip(zip(cases, types), tag.values)
                .map {
                    "        case \(ContractSwiftNames.string($1)): self = .\($0.0)(try \($0.1)(wireJSON: wireJSON))"
                }
                .joined(separator: "\n")
            decoding = """
                    let object = try WireObject(wireJSON)
                    let discriminator: String = try object.required(\(ContractSwiftNames.string(tag.key)))
                    switch discriminator {
                \(branches)
                    default: self = .unknown(type: discriminator, payload: wireJSON)
                    }
                """
            let literals = tag.values.map(ContractSwiftNames.string).joined(separator: ", ")
            unknownEncoding = """

                    // swiftlint:disable:next pattern_matching_keywords
                    case .unknown(let type, let payload):
                        let object = try WireObject(payload)
                        let discriminator: String = try object.required(\(ContractSwiftNames.string(tag.key)))
                        guard discriminator == type, ![\(literals)].contains(type) else {
                            throw WireCodingError(.invalidDiscriminator)
                        }
                        return payload
                """
        } else {
            let attempts = zip(cases, types)
                .map {
                    let action = kind == .anyOf ? "self = .\($0)(value); return" : "matches.append(.\($0)(value))"
                    return "        if let value = try? Self.decode(\($1).self, from: wireJSON) { \(action) }"
                }
                .joined(separator: "\n")
            let prefix =
                kind == .oneOf
                ? "        var matches: [Self] = []\n"
                : "        // anyOf chooses the first valid source branch and preserves its full payload.\n"
            let suffix =
                kind == .oneOf
                ? "        guard matches.count == 1, let value = matches.first else { throw WireCodingError(.typeMismatch) }\n        self = value"
                : "        throw WireCodingError(.typeMismatch)"
            decoding = prefix + attempts + "\n" + suffix
            unknownEncoding = ""
        }
        let complexityNote =
            "    // Pure SDK variant mapping; keep exhaustive dispatch and explicit unknown handling.\n"
            + "    // swiftlint:disable:next cyclomatic_complexity\n"
        // SwiftLint counts the unknown branch and, for encoding, its payload validation guard.
        let decodeComplexityNote = tag != nil && branches.count + 1 > 20 ? complexityNote : ""
        let encodeComplexityNote = tag != nil && branches.count + 2 > 20 ? complexityNote : ""
        return """
            public indirect enum \(name): Sendable, WireCodable {
            \(declarations)\(unknownDeclaration)

            \(decodeComplexityNote)    public init(wireJSON: JSONValue) throws {
            \(decoding)
                }

            \(encodeComplexityNote)    public func wireJSON() throws -> JSONValue {
                    switch self {
            \(encodings)\(unknownEncoding)
                    }
                }

                private static func encode<Value: WireCodable>(_ value: Value) throws -> JSONValue {
            \(kind == .oneOf ? "        let payload = try value.wireJSON()\n        _ = try Self(wireJSON: payload)\n        return payload" : "        try value.wireJSON()")
                }
            \(tag == nil ? """

                private static func decode<Value: WireCodable>(_ type: Value.Type, from json: JSONValue) throws -> Value {
                    try Value(wireJSON: json)
                }
            """ : "")
            }
            """
    }

    func discriminator(_ branches: [String], pointer: String) throws -> (key: String, values: [String])? {
        var candidates: [[String: String]] = []
        for branch in branches {
            guard case .object(let fields, _) = try graph.resolved(branch).kind else { return nil }
            var values: [String: String] = [:]
            for field in fields where field.required {
                if case .enumeration(let literals) = try graph.resolved(field.schema).kind, literals.count == 1 {
                    values[field.key] = literals[0]
                }
            }
            candidates.append(values)
        }
        guard let first = candidates.first else { return nil }
        let keys = first.keys.filter { key in candidates.allSatisfy { $0[key] != nil } }.sorted {
            if $0 == "type" { return true }
            if $1 == "type" { return false }
            return $0 < $1
        }
        guard let key = keys.first else { return nil }
        let values = candidates.compactMap { $0[key] }
        guard Set(values).count == values.count else {
            throw graph.error(pointer, "Discriminator tag collision requires an explicit rule")
        }
        return (key, values)
    }
}
