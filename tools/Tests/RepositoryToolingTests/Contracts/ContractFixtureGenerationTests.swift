import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Compiled contract fixture generation")
struct ContractFixtureGenerationTests {
    @Test func everyCompiledFixtureMatchesTheCurrentEmitter() throws {
        let root = try RepositoryFixture.root()
        let manifest = try ContractProjectionManifest.read(
            Data(contentsOf: root.appendingPathComponent("schemas/projections.json")))
        let fixtures = manifest.contracts.filter { $0.schema == "schemas/fixtures/generation.schema.json" }
        try #require(!fixtures.isEmpty)
        let schema = try Data(contentsOf: root.appendingPathComponent("schemas/fixtures/generation.schema.json"))
        var compared: Set<String> = []
        for fixture in fixtures {
            let graph = try ContractSchemaReader.read(data: schema, rootID: fixture.root)
            let projected = try ContractProjection.apply(graph: graph, rule: fixture)
            var emitter = ContractEmitter(graph: projected)
            let codecs = try emitter.emit()
            let files = try codecs + ContractQualificationEmitter.emit(emitter: emitter).files
            let output = try #require(fixture.output)
            for file in files {
                let path = output + "/" + file.relativePath
                let compiled = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                let emitted = try ContractSwiftFormat.format(file.source)
                #expect(body(emitted) == body(compiled), "Compiled fixture differs from its emitter: \(path)")
                compared.insert(path)
            }
        }
        #expect(compared.count > fixtures.count)
    }

    private func body(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .drop { $0.hasPrefix("//") }
            .joined(separator: "\n")
    }
}
