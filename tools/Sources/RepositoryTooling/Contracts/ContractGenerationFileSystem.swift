import Foundation

public enum ContractGenerationFileSystem {
    public static func generate(root: URL) throws -> [String] {
        let plan = try ContractGenerationPlan.build(root: root)
        let previous = try previousManifest(root: root)
        try validateOwnership(plan, previous: previous, root: root)
        let manager = FileManager.default
        for file in plan.files {
            let url = try ContractGenerationPaths.output(file.relativePath, root: root)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.source.utf8).write(to: url, options: .atomic)
        }
        let current = Set(plan.files.map(\.relativePath))
        for file in previous?.files ?? [] where !current.contains(file.path) {
            let url = try ContractGenerationPaths.output(file.path, root: root)
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        }
        try plan.manifest.data().write(
            to: ContractGenerationPaths.relative(ContractGenerationPaths.manifest, root: root), options: .atomic)
        return plan.files.map(\.relativePath)
    }

    public static func check(root: URL) throws -> [String] {
        let plan = try ContractGenerationPlan.build(root: root)
        let previous = try previousManifest(root: root)
        try validateOwnership(plan, previous: previous, root: root)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LittleSwitch-contract-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for file in plan.files {
            let expected = temporary.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(
                at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.source.utf8).write(to: expected)
            let actual = try ContractGenerationPaths.output(file.relativePath, root: root)
            guard (try? Data(contentsOf: actual)) == (try Data(contentsOf: expected)) else {
                throw ContractGenerationPaths.failure(
                    file.relativePath, "Generated Swift differs; run schemas:generate")
            }
        }
        let manifestURL = try ContractGenerationPaths.relative(ContractGenerationPaths.manifest, root: root)
        guard previous != nil, try Data(contentsOf: manifestURL) == plan.manifest.data() else {
            throw ContractGenerationPaths.failure(
                ContractGenerationPaths.manifest, "Generated manifest differs; run schemas:generate")
        }
        return plan.files.map(\.relativePath)
    }

    private static func previousManifest(root: URL) throws -> ContractGenerationManifest? {
        let url = try ContractGenerationPaths.relative(ContractGenerationPaths.manifest, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let manifest = try JSONDecoder().decode(ContractGenerationManifest.self, from: Data(contentsOf: url))
        guard manifest.formatVersion == 1 else {
            throw ContractGenerationPaths.failure(url.lastPathComponent, "Unsupported manifest version")
        }
        return manifest
    }

    private static func validateOwnership(
        _ plan: ContractGenerationPlan, previous: ContractGenerationManifest?, root: URL
    ) throws {
        let owned = previous?.files.map(\.path) ?? []
        guard Set(owned).count == owned.count else {
            throw ContractGenerationPaths.failure("manifest", "Repeated owned path")
        }
        for path in owned { _ = try ContractGenerationPaths.output(path, root: root) }
        let paths = plan.files.map(\.relativePath)
        guard Set(paths).count == paths.count, Set(paths.map { $0.lowercased() }).count == paths.count else {
            throw ContractGenerationPaths.failure("manifest", "Generated path collision")
        }
        for path in paths {
            let url = try ContractGenerationPaths.output(path, root: root)
            guard owned.contains(path) || !FileManager.default.fileExists(atPath: url.path) else {
                throw ContractGenerationPaths.failure(
                    path, "Refusing to overwrite a file absent from the previous manifest")
            }
        }
    }
}

struct ContractGenerationPlan {
    let files: [GeneratedContractFile]
    let manifest: ContractGenerationManifest

    static func build(root: URL) throws -> Self {
        var inputs: [String: Data] = [:]
        func read(_ path: String) throws -> Data {
            let data = try Data(contentsOf: ContractGenerationPaths.relative(path, root: root))
            inputs[path] = data
            return data
        }
        let projection = try ContractProjectionManifest.read(read("schemas/projections.json"))
        let roots = try JSONDecoder().decode(ContractRootsManifest.self, from: read("schemas/roots.json"))
        let upstream = try JSONDecoder().decode(
            ContractUpstreamManifest.self, from: read("schemas/upstream/manifest.json"))
        let compatibility = try read("schemas/compatibility.json")
        let overrides = try ContractCompatibilityManifest.read(compatibility).overrides
        for rule in overrides {
            guard projection.contracts.contains(where: { $0.root == rule.root && $0.swiftName == rule.projection })
            else {
                throw ContractGenerationPaths.failure(rule.id, "Compatibility projection is not selected")
            }
            for fixture in rule.fixtures { _ = try read(fixture) }
        }
        var files: [GeneratedContractFile] = []
        var qualificationGroups: [String] = []
        func append(_ generated: [GeneratedContractFile], output: String) throws {
            for file in generated {
                let path = output + "/" + file.relativePath
                _ = try ContractGenerationPaths.output(path, root: root)
                files.append(.init(relativePath: path, source: try ContractSwiftFormat.format(file.source)))
            }
        }
        for rule in projection.contracts {
            let path: String
            let schema: Data
            let origin: String
            if let local = rule.schema {
                guard local.hasPrefix("schemas/fixtures/"), rule.output == ContractGenerationPaths.outputRoots[1] else {
                    throw ContractGenerationPaths.failure(
                        local, "Local schemas are restricted to compiled test fixtures")
                }
                path = local
                schema = try read(path)
                origin = "Local qualification fixture (not an SDK contract)"
            } else {
                guard let entry = roots.roots.first(where: { $0.name == rule.root }) else {
                    throw ContractGenerationPaths.failure(rule.root, "Unknown SDK root")
                }
                path = "schemas/upstream/" + entry.schema
                schema = try read(path)
                guard let artifact = upstream.artifacts.first(where: { $0.path == entry.schema }),
                    artifact.sha256 == ContractGenerationManifest.hash(schema)
                else {
                    throw ContractGenerationPaths.failure(path, "Upstream schema hash mismatch")
                }
                guard let source = upstream.sources?.first(where: { $0.id == entry.sdk }) else {
                    throw ContractGenerationPaths.failure(path, "Missing SDK provenance")
                }
                origin = "SDK: \(source.package) \(source.version)"
            }
            var graph = try ContractSchemaReader.read(data: schema, rootID: rule.root)
            graph.swiftName = rule.swiftName
            graph = try ContractCompatibility.apply(graph: graph, rules: overrides, projection: rule)
            var projected = try ContractProjection.apply(graph: graph, rule: rule)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            projected.provenance = [
                origin,
                "Schema SHA256: " + ContractGenerationManifest.hash(schema),
                "Projection SHA256: " + ContractGenerationManifest.hash(try encoder.encode(rule)),
                "Compatibility SHA256: " + ContractGenerationManifest.hash(compatibility),
            ]
            var emitter = ContractEmitter(graph: projected)
            let generated = try emitter.emit()
            let output = rule.output ?? ContractGenerationPaths.outputRoots[0]
            guard ContractGenerationPaths.outputRoots.contains(output) else {
                throw ContractGenerationPaths.failure(output, "Unowned output directory")
            }
            try append(generated, output: output)
            let qualification = try ContractQualificationEmitter.emit(emitter: emitter)
            try append(qualification.files, output: ContractGenerationPaths.outputRoots[1])
            qualificationGroups.append(qualification.groupName)
        }
        try append(
            ContractQualificationEmitter.support(groups: qualificationGroups),
            output: ContractGenerationPaths.outputRoots[1])
        files.sort { $0.relativePath < $1.relativePath }
        let manifest = ContractGenerationManifest(
            formatVersion: 1,
            generator: "littleswitch-tools/contracts-v1",
            inputs: inputs.keys.sorted().compactMap { path in
                inputs[path].map { .init(path: path, sha256: ContractGenerationManifest.hash($0)) }
            },
            files: files.map {
                .init(path: $0.relativePath, sha256: ContractGenerationManifest.hash(Data($0.source.utf8)))
            }
        )
        return Self(files: files, manifest: manifest)
    }

}
