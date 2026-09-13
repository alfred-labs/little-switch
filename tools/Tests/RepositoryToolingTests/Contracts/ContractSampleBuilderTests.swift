import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Minimal contract sample values")
struct ContractSampleBuilderTests {
    @Test func exactJSONEscapingAndScalarValues() throws {
        let text = "quoted\" \\ \n\u{0} café"
        let json = ContractSampleValue.object([
            "text": .string(text), "empty": .object([:]), "yes": .boolean(true), "no": .boolean(false),
        ]).json
        let decoded = try JSONDecoder().decode(ContractSchemaValue.self, from: Data(json.utf8))
        #expect(decoded.object?["text"] == .string(text))
        #expect(decoded.object?["empty"] == .object([:]))
        #expect(decoded.object?["yes"] == .boolean(true))
        #expect(decoded.object?["no"] == .boolean(false))
        let builder = try builder(#"{"type":"boolean"}"#)
        #expect(try builder.value("#") == .boolean(false))
        #expect(try builder.value("#", full: true) == .boolean(true))
        #expect(try self.builder(#"{"type":"null"}"#).value("#") == .null)
    }

    @Test func nullableArraysUseValueAndNullAndTypedExtrasUseTheirSchema() throws {
        let builder = try builder(#"{"type":"array","items":{"type":["number","null"]}}"#)
        #expect(try builder.value("#", full: true) == .array([.number("9007199254740993"), .null]))
        var emitter = ContractEmitter(
            graph: try self.builder(#"{"type":"object","additionalProperties":{"type":"number"}}"#).graph)
        _ = try emitter.emit()
        let samples = try ContractCodecSamples.make(emitter: emitter, pointer: "#", name: "Example")
        #expect(samples.first { $0.label == "minimal" }?.input == .object([:]))
        #expect(samples.first { $0.label == "full" }?.input == .object(["__wire_unknown__": .number("1e400")]))
        #expect(!samples.contains { $0.label == "collision" })
    }

    @Test func forbiddenExtrasAndOpenEnumsHaveDistinctCases() throws {
        var graph = try builder(
            #"{"type":"object","properties":{"kind":{"enum":["__wire_unknown__"]}},"required":["kind"],"additionalProperties":false}"#
        ).graph
        graph.nodes["#/known"] = graph.nodes["#/properties/kind"].map {
            ContractNode(pointer: "#/known", kind: $0.kind, annotations: [:])
        }
        graph.nodes["#/properties/kind"]?.kind = .openEnum("#/known")
        var emitter = ContractEmitter(graph: graph)
        _ = try emitter.emit()
        let samples = try ContractCodecSamples.make(emitter: emitter, pointer: "#", name: "Example")
        #expect(samples.contains { $0.label == "open:kind" && $0.failure == nil })
        #expect(samples.contains { $0.label == "forbidden-extra" && $0.failure?.kind == "typeMismatch" })
        let known = try ContractCodecSamples.make(emitter: emitter, pointer: "#/known", name: "Known")
        #expect(known.first { $0.label == "invalid-enum" }?.input == .string("__wire_unknown___"))
    }

    @Test func recursionUsesALeafAndRejectsGraphsWithoutFiniteValues() throws {
        let terminating = try builder(
            ##"{"anyOf":[{"type":"object","properties":{"next":{"$ref":"#"}},"required":["next"]},{"type":"string"}]}"##
        )
        #expect(try terminating.value("#") == .string("wire sample"))
        let unending = try builder(
            ##"{"anyOf":[{"type":"object","properties":{"next":{"$ref":"#"}},"required":["next"]},{"type":"object","properties":{"again":{"$ref":"#"}},"required":["again"]}]}"##
        )
        #expect(throws: unending.graph.error("#", "Automatic qualification cannot construct an accepted union witness"))
        {
            try unending.value("#")
        }
        let record = try builder(##"{"type":"object","properties":{"next":{"$ref":"#"}},"required":["next"]}"##)
        #expect(throws: record.graph.error("#", "Recursive qualification value")) { try record.value("#") }
    }

    @Test func malformedSampleRequestsFailWithDomainDiagnostics() throws {
        var graph = try builder(#"{"type":"string"}"#).graph
        #expect(throws: graph.error("#", "Qualification requires an emitted declaration")) {
            try ContractCodecSamples.make(emitter: .init(graph: graph), pointer: "#", name: "Example")
        }
        graph.nodes["#"]?.kind = .enumeration([])
        #expect(throws: graph.error("#", "Empty enum cannot be qualified")) {
            try ContractSampleBuilder(graph: graph).value("#")
        }
    }

    private func builder(_ schema: String) throws -> ContractSampleBuilder {
        ContractSampleBuilder(graph: try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example"))
    }
}
