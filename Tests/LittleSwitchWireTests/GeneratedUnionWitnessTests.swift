import LittleSwitchWire
import LittleSwitchWireContractFixtures
import Testing

@Suite("Generated union witness semantics")
struct GeneratedUnionWitnessTests {
    @Test func oneOfAcceptsExclusiveValuesAndRejectsAmbiguityOnDecodeAndEncode() throws {
        for value in ["b", "c"] {
            #expect(try FixtureOverlappingOne(wireJSON: .string(value)).wireJSON() == .string(value))
        }
        #expect(throws: WireCodingError(.typeMismatch)) {
            try FixtureOverlappingOne(wireJSON: .string("a"))
        }
        #expect(throws: WireCodingError(.typeMismatch)) {
            try FixtureOverlappingOne.variant1(.valueA).wireJSON()
        }
        let nested = try JSONValue.parse(#"{"choice":"b","extra":1e400}"#)
        #expect(try FixtureNestedOverlap(wireJSON: nested).wireJSON() == nested)
        #expect(throws: WireCodingError(.typeMismatch, path: ["choice"])) {
            try FixtureNestedOverlap(wireJSON: JSONValue.parse(#"{"choice":"a"}"#))
        }
    }

    @Test func anyOfWithOpaqueBranchAcceptsNullAndRetainsExactJSON() throws {
        for value in [
            JSONValue.null, .string("text"), try JSONValue.parse(#"{"large":1e400,"integer":9007199254740993}"#),
        ] {
            #expect(try FixtureOpaqueAny(wireJSON: value).wireJSON() == value)
        }
        #expect(try FixtureOpaqueAny.variant2("text").wireJSON() == .string("text"))
    }

    @Test func aPayloadNamedDiscriminatorRetainsKnownAndUnknownValues() throws {
        let known = try JSONValue.parse(#"{"__wire_payload__":"a"}"#)
        #expect(try FixturePayloadTag(wireJSON: known).wireJSON() == known)
        let unknown = try JSONValue.parse(#"{"__wire_payload__":"future","extra":1e400}"#)
        #expect(try FixturePayloadTag(wireJSON: unknown).wireJSON() == unknown)
        #expect(throws: WireCodingError(.unexpectedNull, path: ["__wire_payload__"])) {
            try FixturePayloadTag(wireJSON: JSONValue.parse(#"{"__wire_payload__":null}"#))
        }
    }
}
