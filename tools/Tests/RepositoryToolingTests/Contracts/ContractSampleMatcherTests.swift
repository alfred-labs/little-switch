import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Qualification acceptance and bounded alternatives")
struct ContractSampleMatcherTests {
    @Test func requiredPropertiesAndTypedAdditionalValuesRemainStrict() throws {
        let builder = try builder(
            #"""
            {"type":"object","properties":{
              "name":{"type":"string"},"flag":{"type":"boolean"},
              "flags":{"type":"array","items":{"const":true}}
            },"required":["name"],"additionalProperties":{"type":"number"}}
            """#)
        let matcher = ContractSampleMatcher(graph: builder.graph)
        #expect(try matcher.accepts(.object(["name": .string("sample"), "extra": .number("1e400")]), at: "#"))
        #expect(
            try matcher.accepts(
                .object(["name": .string("sample"), "flag": .boolean(false), "flags": .array([.boolean(true)])]),
                at: "#"))
        for value: ContractSampleValue in [
            .string("object required"), .object([:]), .object(["name": .boolean(true)]),
            .object(["name": .string("sample"), "extra": .boolean(true)]),
            .object(["name": .string("sample"), "flags": .array([.boolean(false)])]),
            .object(["name": .string("sample"), "flags": .boolean(true)]),
        ] {
            #expect(try !matcher.accepts(value, at: "#"))
        }
    }

    @Test func forbiddenExtrasAndNullableArrayItemsFollowTheirContracts() throws {
        let builder = try builder(
            #"{"type":"object","properties":{"items":{"type":"array","items":{"type":["string","null"]}}},"required":["items"],"additionalProperties":false}"#
        )
        let matcher = ContractSampleMatcher(graph: builder.graph)
        #expect(try matcher.accepts(.object(["items": .array([.string("text"), .null])]), at: "#"))
        #expect(try !matcher.accepts(.object(["items": .array([]), "extra": .null]), at: "#"))
        #expect(try !matcher.accepts(.object(["items": .array([.number("1")])]), at: "#"))
        #expect(try matcher.accepts(.null, at: "#/properties/items/items/type/1"))
    }

    @Test func recordAlternativesAvoidACartesianProduct() throws {
        let builder = try builder(
            #"{"type":"object","properties":{"flag":{"type":"boolean"},"kind":{"enum":["first","second"]}}}"#)
        let candidates = try builder.candidates("#", full: true)
        #expect(candidates.contains(.object([:])))
        #expect(candidates.contains(.object(["flag": .boolean(false), "kind": .string("first")])))
        #expect(candidates.contains(.object(["flag": .boolean(true), "kind": .string("second")])))
        #expect(!candidates.contains(.object(["flag": .boolean(false), "kind": .string("second")])))
    }

    @Test func arraysOpenEnumsAndOpaqueValuesHaveFiniteAlternativeSets() throws {
        let array = try builder(#"{"type":"array","items":{"enum":["first","second"]}}"#)
        let items = try array.candidates("#", full: true)
        #expect(items.contains(.array([])))
        #expect(items.contains(.array([.string("second")])))
        var graph = try builder(
            #"{"type":"object","properties":{"value":{"type":"string"},"known":{"enum":["__wire_sample__"]}}}"#
        ).graph
        let strings = try ContractSampleBuilder(graph: graph).candidates("#/properties/value", full: true)
        #expect(strings.contains(.string("__wire_sample___")))
        graph.nodes["#/properties/value"]?.kind = .openEnum("#/properties/known")
        let values = try ContractSampleBuilder(graph: graph).candidates("#/properties/value", full: true)
        #expect(values == [.string("__wire_sample__"), .string("__wire_sample___")])
        #expect(try ContractSampleMatcher(graph: graph).accepts(.string("future"), at: "#/properties/value"))
        let opaque = try builder(#"{}"#).candidates("#", full: true)
        #expect(opaque.contains(.null))
        #expect(opaque.contains(.number("1e400")))
        #expect(try builder(#"{"const":true}"#).candidates("#", full: false) == [.boolean(true)])
        #expect(try builder(#"{"type":"number"}"#).candidates("#", full: true) == [.number("1e400")])
    }

    @Test func finiteAlternativesSurviveRecursiveChildren() throws {
        let array = try builder(
            #"""
            {"definitions":{"Node":{"type":"object","properties":{"next":{"$ref":"#/definitions/Node"}}}},
             "type":"array","items":{"$ref":"#/definitions/Node"}}
            """#)
        #expect(try array.candidates("#", full: true) == [.array([.object([:])]), .array([])])

        let record = try builder(
            #"""
            {"definitions":{"Node":{"type":"object","properties":{"next":{"$ref":"#/definitions/Node"}}}},
             "type":"object","properties":{"node":{"$ref":"#/definitions/Node"}},"required":["node"]}
            """#)
        #expect(try record.candidates("#", full: true) == [.object(["node": .object([:])])])

        let union = try builder(
            #"""
            {"anyOf":[
              {"type":"object","properties":{"next":{"$ref":"#/anyOf/0"}},"required":["next"]},
              {"enum":["leaf"]}
            ]}
            """#)
        #expect(try union.candidates("#", full: true) == [.string("leaf")])
        #expect(try ContractSampleMatcher(graph: union.graph).accepts(.string("leaf"), at: "#"))
    }

    private func builder(_ schema: String) throws -> ContractSampleBuilder {
        ContractSampleBuilder(graph: try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Example"))
    }
}
