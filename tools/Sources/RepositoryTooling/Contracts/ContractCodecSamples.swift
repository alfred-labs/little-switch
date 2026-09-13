enum ContractCodecSamples {
    static func make(emitter: ContractEmitter, pointer: String, name: String) throws -> [ContractCodecSample] {
        let node = try emitter.graph.resolved(pointer)
        let builder = ContractSampleBuilder(graph: emitter.graph)
        switch node.kind {
        case .enumeration(let values):
            return values.map { .init(label: "enum:" + $0, input: .string($0)) }
                + [
                    .init(
                        label: "invalid-enum",
                        input: .string(unknown(excluding: values)),
                        failure: .init(kind: "invalidDiscriminator"))
                ]
        case .booleanConstant(let value):
            return [
                .init(label: "literal", input: .boolean(value)),
                .init(label: "invalid-literal", input: .boolean(!value), failure: .init(kind: "invalidDiscriminator")),
            ]
        // swiftlint:disable:next pattern_matching_keywords
        case .object(let fields, let additional):
            return try record(fields, additional: additional, builder: builder, pointer: pointer, name: name)
        case .union(_, let branches):
            return try union(branches, emitter: emitter, builder: builder, pointer: pointer, name: name)
        default: throw emitter.graph.error(pointer, "Qualification requires an emitted declaration")
        }
    }

    private static func record(
        _ fields: [ContractField],
        additional: ContractAdditionalFields,
        builder: ContractSampleBuilder,
        pointer: String,
        name: String
    ) throws -> [ContractCodecSample] {
        let minimal = ContractSampleValue.object(try builder.recordFields(fields, pointer: pointer, full: false))
        var full = try builder.recordFields(fields, pointer: pointer, full: true)
        let extraKey = unknown(excluding: fields.map(\.key))
        switch additional {
        case .allowed: full[extraKey] = .opaque
        case .typed(let schema): full[extraKey] = try builder.value(schema, full: true)
        case .forbidden: break
        }
        var samples: [ContractCodecSample] = [
            .init(label: "minimal", input: minimal), .init(label: "full", input: .object(full)),
            .init(label: "invalid-root", input: .null, failure: .init(kind: "typeMismatch")),
        ]
        let emitter = ContractEmitter(graph: builder.graph)
        for field in fields {
            if field.required {
                var missing = full
                missing[field.key] = nil
                samples.append(
                    .init(
                        label: "missing:" + field.key,
                        input: .object(missing),
                        failure: .init(kind: "missingField", path: [field.key])))
            }
            var null = full
            null[field.key] = .null
            let nullable = try emitter.presence(field.schema).nullable
            samples.append(
                .init(
                    label: "null:" + field.key,
                    input: .object(null),
                    failure: nullable ? nil : .init(kind: "unexpectedNull", path: [field.key])))
            if case .openEnum = try builder.graph.resolved(emitter.presence(field.schema).base).kind {
                var future = full
                future[field.key] = .string("__wire_future_value__")
                samples.append(.init(label: "open:" + field.key, input: .object(future)))
            }
        }
        if let first = fields.first {
            samples.append(
                .init(
                    label: "collision",
                    input: minimal,
                    failure: .init(kind: "additionalFieldCollision", path: [first.key]),
                    operation:
                        "var value = try \(name)(wireJSON: json)\nvalue.additionalFields[\(ContractSwiftNames.string(first.key))] = .null\nreturn try value.wireJSON()"
                ))
        }
        if case .forbidden = additional {
            var unknown = full
            unknown[extraKey] = .opaque
            samples.append(
                .init(label: "forbidden-extra", input: .object(unknown), failure: .init(kind: "typeMismatch")))
        }
        return samples
    }

    private static func union(
        _ branches: [String], emitter: ContractEmitter, builder: ContractSampleBuilder, pointer: String, name: String
    ) throws -> [ContractCodecSample] {
        var emitter = emitter
        let tag = try emitter.discriminator(branches, pointer: pointer)
        let matcher = ContractSampleMatcher(graph: emitter.graph)
        var samples: [ContractCodecSample] = []
        var rejected: ContractSampleValue?
        for (index, branch) in branches.enumerated() {
            var value = try builder.value(branch, full: true)
            if try !matcher.accepts(value, at: pointer) {
                rejected = rejected ?? value
                let candidates = try builder.candidates(branch, full: true)
                guard let witness = try candidates.first(where: { try matcher.accepts($0, at: pointer) }) else {
                    throw emitter.graph.error(
                        branch,
                        "Automatic qualification cannot construct an exclusive union-branch witness; extend the bounded sample search or select a projection"
                    )
                }
                value = witness
            }
            samples.append(.init(label: "branch:\(index)", input: value))
            if let malformed = try malformedBranch(value, graph: emitter.graph, pointer: branch, tag: tag?.key) {
                samples.append(
                    .init(
                        label: "malformed-branch:\(index)", input: malformed.input, failure: malformed.failure))
            }
            if tag == nil {
                let type = try emitter.type(branch, suggested: name + "Variant\(index + 1)")
                samples.append(
                    .init(
                        label: "encode-branch:\(index)",
                        input: value,
                        operation: "return try \(name).variant\(index + 1)(\(type)(wireJSON: json)).wireJSON()"))
            }
        }
        if let tag {
            let value = unknown(excluding: tag.values)
            let payloadKey = unknown(excluding: [tag.key])
            let input: ContractSampleValue = .object([tag.key: .string(value), payloadKey: .opaque])
            samples.append(.init(label: "unknown", input: input))
            samples.append(
                .init(
                    label: "unknown-mismatch",
                    input: input,
                    failure: .init(kind: "invalidDiscriminator"),
                    operation:
                        "return try \(name).unknown(type: \(ContractSwiftNames.string(value + "_mismatch")), payload: json).wireJSON()"
                ))
            samples.append(
                .init(label: "missing-tag", input: .object([:]), failure: .init(kind: "missingField", path: [tag.key])))
        } else {
            let nullable = try matcher.accepts(.null, at: pointer)
            samples.append(
                .init(label: "null-union", input: .null, failure: nullable ? nil : .init(kind: "typeMismatch")))
            if let rejected {
                samples.append(.init(label: "rejected-union", input: rejected, failure: .init(kind: "typeMismatch")))
            }
        }
        return samples
    }

    private static func malformedBranch(
        _ value: ContractSampleValue, graph: ContractGraph, pointer: String, tag: String?
    ) throws -> ContractCodecSample? {
        guard let tag,
            case .object(let fields, _) = try graph.resolved(pointer).kind,
            let required = fields.first(where: { $0.required && $0.key != tag }),
            case .object(var malformed) = value
        else { return nil }
        malformed[required.key] = nil
        return .init(label: "", input: .object(malformed), failure: .init(kind: "missingField", path: [required.key]))
    }

    private static func unknown(excluding values: [String]) -> String {
        var value = "__wire_unknown__"
        while values.contains(value) { value += "_" }
        return value
    }
}
