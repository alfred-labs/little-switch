import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Automatic codec qualification")
struct ContractQualificationTests {
    @Test func qualificationBasenamesAreUniqueAcrossTypesAndProjections() throws {
        var files: [GeneratedContractFile] = []
        var groups: [String] = []
        for name in ["First", "Second"] {
            var graph = try emitter(#"{"type":"object","properties":{"value":{"enum":["one","two"]}}}"#).graph
            graph.swiftName = name
            var emitter = ContractEmitter(graph: graph)
            files += try emitter.emit()
            let qualification = try ContractQualificationEmitter.emit(emitter: emitter)
            files += qualification.files
            groups.append(qualification.groupName)
        }
        files += ContractQualificationEmitter.support(groups: groups)
        let basenames = files.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent }
        #expect(Set(basenames).count == files.count)
    }

    @Test func recordSamplesDistinguishAllPresenceStatesAndErrors() throws {
        var emitter = try emitter(
            #"""
            {"type":"object","properties":{
              "required":{"type":"string"},"required_nullable":{"type":["string","null"]},
              "optional":{"type":"string"},"presence":{"type":["string","null"]}
            },"required":["required","required_nullable"]}
            """#)
        _ = try emitter.emit()
        let samples = try ContractCodecSamples.make(emitter: emitter, pointer: "#", name: "Example")
        #expect(
            samples.first { $0.label == "minimal" }?.input
                == .object(["required": .string("wire sample"), "required_nullable": .string("wire sample")]))
        #expect(samples.first { $0.label == "missing:required" }?.failure?.kind == "missingField")
        #expect(samples.first { $0.label == "null:required" }?.failure?.kind == "unexpectedNull")
        #expect(samples.first { $0.label == "null:optional" }?.failure?.path == ["optional"])
        #expect(samples.first { $0.label == "null:required_nullable" }?.failure == nil)
        #expect(samples.first { $0.label == "null:presence" }?.failure == nil)
        #expect(samples.first { $0.label == "collision" }?.failure?.kind == "additionalFieldCollision")
        #expect(samples.first { $0.label == "full" }?.input.json.contains("1e400") == true)
    }

    @Test func enumAndTaggedUnionSamplesUseEveryAllocatedDeclaration() throws {
        var emitter = try emitter(
            #"""
            {"anyOf":[
              {"type":"object","properties":{"type":{"const":"first"},"value":{"enum":["one","two"]}},"required":["type","value"]},
              {"type":"object","properties":{"type":{"const":"second"}},"required":["type"]}
            ]}
            """#)
        _ = try emitter.emit()
        let output = try ContractQualificationEmitter.emit(emitter: emitter)
        #expect(output.files.count == emitter.names.count + 1)
        #expect(try ContractQualificationEmitter.emit(emitter: emitter).files == output.files)
        let samples = try ContractCodecSamples.make(emitter: emitter, pointer: "#", name: "Example")
        #expect(samples.filter { $0.label.hasPrefix("branch:") }.count == 2)
        #expect(samples.contains { $0.label == "unknown" && $0.failure == nil })
        #expect(samples.contains { $0.label == "unknown-mismatch" && $0.failure?.kind == "invalidDiscriminator" })
        #expect(
            samples.first { $0.label == "malformed-branch:0" }?.failure == .init(kind: "missingField", path: ["value"]))
        let enumeration = try ContractCodecSamples.make(
            emitter: emitter, pointer: "#/anyOf/0/properties/value", name: "ExampleFirstValue")
        #expect(enumeration.filter { $0.failure == nil }.map(\.input) == [.string("one"), .string("two")])
    }

    @Test func recursiveSamplesTerminateAndOpaqueNumbersRemainExact() throws {
        let emitter = try emitter(
            ##"{"type":"object","properties":{"children":{"type":"array","items":{"$ref":"#"}},"opaque":{}},"required":["children","opaque"]}"##
        )
        let builder = ContractSampleBuilder(graph: emitter.graph)
        let value = try builder.value("#", full: true)
        #expect(value.json.contains("1e400"))
        #expect(value.json.contains("9007199254740993"))
        #expect(value.json.contains("null"))
        #expect(value.json.count < 500)
    }

    @Test func largeSampleSetsAreSplitIntoLintedOwnedFiles() throws {
        let values = (0..<50).map { "value_\($0)" }
        let schema = try JSONEncoder().encode(["enum": values])
        var emitter = ContractEmitter(graph: try ContractSchemaReader.read(data: schema, rootID: "LargeEnum"))
        _ = try emitter.emit()
        let output = try ContractQualificationEmitter.emit(emitter: emitter)
        let files = output.files + ContractQualificationEmitter.support(groups: [output.groupName])
        #expect(output.files.filter { $0.relativePath.hasPrefix("Qualification/LargeEnum/") }.count > 2)
        #expect(
            output.files.contains {
                $0.relativePath.hasPrefix("Qualification/LargeEnum/") && $0.source.contains(".flatMap")
            })
        #expect(ContractQualificationEmitter.support(groups: []).isEmpty)
        try withTemporaryDirectory { root in
            var paths: [String] = []
            for file in files {
                let url = root.appendingPathComponent(file.relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(ContractSwiftFormat.format(file.source).utf8).write(to: url)
                paths.append(url.path)
            }
            let repository = try RepositoryFixture.root()
            let lint = try RepositoryProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swiftlint", "lint", "--strict", "--quiet", "--no-cache", "--config",
                    repository.appendingPathComponent(".swiftlint.yml").path,
                ] + paths,
                directory: root)
            #expect(lint.status == 0, "\(lint.stdout)\(lint.stderr)")
        }
    }

    private func emitter(_ schema: String) throws -> ContractEmitter {
        ContractEmitter(graph: try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example"))
    }
}
