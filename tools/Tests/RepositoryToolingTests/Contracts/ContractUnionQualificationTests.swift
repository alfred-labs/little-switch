import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Union qualification witnesses")
struct ContractUnionQualificationTests {
    @Test func nestedTaggedUnknownParticipatesInOuterOneOfMatches() throws {
        let schema = #"""
            {"oneOf":[
              {"anyOf":[
                {"type":"object","properties":{"type":{"const":"a"}},"required":["type"]},
                {"type":"object","properties":{"type":{"const":"b"}},"required":["type"]}
              ]},
              {"type":"object","properties":{"type":{"const":"c"}},"required":["type"]}
            ]}
            """#
        let graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example")
        #expect(try !ContractSampleMatcher(graph: graph).accepts(.object(["type": .string("c")]), at: "#"))
        #expect(
            throws: graph.error(
                "#/oneOf/1",
                "Automatic qualification cannot construct an exclusive union-branch witness; extend the bounded sample search or select a projection"
            )
        ) {
            try samples(schema)
        }
    }

    @Test func taggedMatchingKeepsMalformedKnownTagsStrictAndUnknownTagsOpaque() throws {
        let schema = #"""
            {"anyOf":[
              {"type":"object","properties":{"type":{"const":"a"},"text":{"type":"string"}},"required":["type","text"]},
              {"type":"object","properties":{"type":{"const":"b"}},"required":["type"]}
            ]}
            """#
        let matcher = ContractSampleMatcher(
            graph: try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example"))
        #expect(try matcher.accepts(.object(["type": .string("c"), "text": .opaque]), at: "#"))
        #expect(try !matcher.accepts(.object(["type": .string("a")]), at: "#"))
        #expect(try !matcher.accepts(.object(["type": .string("a"), "text": .boolean(true)]), at: "#"))
        #expect(try matcher.accepts(.object(["type": .string("a"), "text": .string("text")]), at: "#"))
        #expect(try !matcher.accepts(.object(["type": .boolean(true)]), at: "#"))
        #expect(try !matcher.accepts(.object([:]), at: "#"))
    }

    @Test func overlappingOneOfSelectsExclusiveEnumValues() throws {
        let samples = try samples(#"{"oneOf":[{"enum":["a","b"]},{"enum":["a","c"]}]}"#)
        #expect(samples.first { $0.label == "branch:0" }?.input == .string("b"))
        #expect(samples.first { $0.label == "branch:1" }?.input == .string("c"))
        #expect(samples.contains { $0.input == .string("a") && $0.failure?.kind == "typeMismatch" })
    }

    @Test func nestedOneOfSelectsAnAcceptedWitnessForItsContainingRecord() throws {
        let samples = try samples(
            #"{"type":"object","properties":{"choice":{"oneOf":[{"enum":["a","b"]},{"enum":["a","c"]}]}},"required":["choice"]}"#
        )
        #expect(samples.first { $0.label == "minimal" }?.input == .object(["choice": .string("b")]))
    }

    @Test func opaqueAnyOfQualifiesAcceptedNullWithoutExpectingAnError() throws {
        let samples = try samples(#"{"anyOf":[{},{"type":"string"}]}"#)
        #expect(samples.contains { $0.input == .null && $0.failure == nil })
        #expect(!samples.contains { $0.input == .null && $0.failure != nil })
    }

    @Test func recordAndNestedUnionWitnessesCanAvoidAnOverlappingValue() throws {
        let records = try samples(
            #"""
            {"oneOf":[
              {"type":"object","properties":{"kind":{"enum":["a","b"]}},"required":["kind"]},
              {"type":"object","properties":{"kind":{"enum":["a","c"]}},"required":["kind"]}
            ]}
            """#
        )
        #expect(records.first { $0.label == "branch:0" }?.input == .object(["kind": .string("b")]))
        #expect(records.first { $0.label == "branch:1" }?.input == .object(["kind": .string("c")]))
        let nested = try samples(#"{"oneOf":[{"anyOf":[{"enum":["a","b"]},{"enum":["d"]}]},{"enum":["a","c"]}]}"#)
        #expect(nested.first { $0.label == "branch:0" }?.input == .string("b"))
        #expect(nested.first { $0.label == "branch:1" }?.input == .string("c"))
    }

    @Test func anUnwitnessedBranchReportsQualificationLimitsWithItsSourcePointer() throws {
        let schema = #"{"oneOf":[{"enum":["a"]},{"enum":["a","b"]}]}"#
        let graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example")
        #expect(try ContractSampleMatcher(graph: graph).accepts(.string("b"), at: "#"))
        #expect(
            throws: graph.error(
                "#/oneOf/0",
                "Automatic qualification cannot construct an exclusive union-branch witness; extend the bounded sample search or select a projection"
            )
        ) {
            try samples(schema)
        }
    }

    @Test func arbitraryDiscriminatorCannotCollideWithTheSyntheticPayloadKey() throws {
        let samples = try samples(
            #"""
            {"anyOf":[
              {"type":"object","properties":{"__wire_payload__":{"const":"a"}},"required":["__wire_payload__"]},
              {"type":"object","properties":{"__wire_payload__":{"const":"b"}},"required":["__wire_payload__"]}
            ]}
            """#
        )
        let sample = try #require(samples.first { $0.label == "unknown" })
        guard case .object(let fields) = sample.input else {
            Issue.record("Unknown tagged payload must remain an object")
            return
        }
        #expect(fields.count == 2)
        #expect(fields["__wire_payload__"] == .string("__wire_unknown__"))
        #expect(fields.values.contains(.opaque))
    }

    private func samples(_ schema: String) throws -> [ContractCodecSample] {
        var emitter = ContractEmitter(graph: try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example"))
        _ = try emitter.emit()
        return try ContractCodecSamples.make(emitter: emitter, pointer: "#", name: "Example")
    }
}
