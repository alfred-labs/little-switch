import Foundation

struct ContractQualificationOutput {
    let files: [GeneratedContractFile]
    let groupName: String
}

enum ContractQualificationEmitter {
    static func emit(emitter: ContractEmitter) throws -> ContractQualificationOutput {
        var files: [GeneratedContractFile] = []
        var groups: [String] = []
        for (pointer, name) in emitter.names.sorted(by: { $0.value < $1.value }) {
            let samples = try ContractCodecSamples.make(emitter: emitter, pointer: pointer, name: name)
            let rows = samples.map { row($0, name: name) }
            let chunks = chunks(rows)
            let typeGroup = group(name)
            var children: [String] = []
            for (index, chunk) in chunks.enumerated() {
                let child = chunks.count == 1 ? typeGroup : typeGroup + "Part\(index + 1)"
                children.append(child)
                let source = """
                    \(header(emitter.graph, pointer: pointer))
                    import LittleSwitchWire

                    enum \(child) {
                        static let samples: [WireGeneratedSample] = [
                    \(chunk.joined(separator: ",\n"))
                        ]
                    }
                    """
                files.append(.init(relativePath: "Qualification/\(name)/\(child).swift", source: source))
            }
            if chunks.count > 1 {
                files.append(
                    registry(name: typeGroup, groups: children, path: "Qualification/\(name)/\(typeGroup).swift"))
            }
            groups.append(typeGroup)
        }
        let projectionGroup = group("projection:" + emitter.graph.swiftName)
        files.append(
            registry(name: projectionGroup, groups: groups, path: "Qualification/\(projectionGroup).swift")
        )
        return .init(files: files.sorted { $0.relativePath < $1.relativePath }, groupName: projectionGroup)
    }

    static func support(groups: [String]) -> [GeneratedContractFile] {
        guard !groups.isEmpty else { return [] }
        let source = """
            // Generated codec qualification support. Do not edit.
            import LittleSwitchWire

            public struct WireGeneratedSample: Sendable {
                public let name: String
                public let input: String
                public let expectedError: WireCodingError?
                public let operation: @Sendable (JSONValue) throws -> JSONValue
            }
            """
        return [
            .init(relativePath: "Qualification/WireGeneratedSample.swift", source: source),
            registry(
                name: "WireGeneratedQualification",
                groups: groups,
                path: "Qualification/WireGeneratedQualification.swift",
                publicAPI: true),
        ]
    }

    private static func row(_ sample: ContractCodecSample, name: String) -> String {
        let input = sample.input.json
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(ContractSwiftNames.string(String($0)).dropFirst().dropLast()) }
            .joined(separator: "\n")
        let error =
            sample.failure.map { failure in
                ".init(.\(failure.kind), path: [\(failure.path.map(ContractSwiftNames.string).joined(separator: ", "))])"
            } ?? "nil"
        let operation = sample.operation ?? "return try \(name)(wireJSON: json).wireJSON()"
        let source = """
            .init(
                name: \(ContractSwiftNames.string(name + "." + sample.label)),
                input: ""\"
            \(input)
            ""\",
                expectedError: \(error)
            ) { json in
                \(operation.replacingOccurrences(of: "\n", with: "\n    "))
            }
            """
        return "        " + source.replacingOccurrences(of: "\n", with: "\n        ")
    }

    private static func chunks(_ rows: [String]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var lines = 0
        for row in rows {
            let size = row.components(separatedBy: "\n").count
            if !current.isEmpty, lines + size > 200 {
                result.append(current)
                current = []
                lines = 0
            }
            current.append(row)
            lines += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func registry(
        name: String, groups: [String], path: String, publicAPI: Bool = false
    ) -> GeneratedContractFile {
        let access = publicAPI ? "public " : ""
        let values = groups.sorted().map { "        \($0).samples" }.joined(separator: ",\n")
        let source = """
            // Generated codec qualification registry. Do not edit.
            \(access)enum \(name) {
                \(access)static let samples: [WireGeneratedSample] = [
            \(values)
                ].flatMap(\\.self)
            }
            """
        return .init(relativePath: path, source: source)
    }

    private static func group(_ identity: String) -> String {
        "WireSamples" + ContractGenerationManifest.hash(Data(identity.utf8)).prefix(12)
    }

    private static func header(_ graph: ContractGraph, pointer: String) -> String {
        (["Generated codec qualification. Do not edit.", "Source: \(graph.rootID) \(pointer)"] + graph.provenance)
            .map { "// " + $0.components(separatedBy: .newlines).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
