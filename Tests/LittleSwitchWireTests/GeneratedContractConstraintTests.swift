import LittleSwitchWire
import LittleSwitchWireContractFixtures
import Testing

@Suite("Compiled generated composition constraints")
struct GeneratedContractConstraintTests {
    @Test func recordFieldsDoNotCollideWithCodecLocals() throws {
        let json = try JSONValue.parse(#"{"object":"message","value":"payload","vendor":1e400}"#)
        let record = try FixtureLocalNames(wireJSON: json)
        #expect(record.object == "message")
        #expect(record.value == "payload")
        #expect(try record.wireJSON() == json)
        #expect(
            try FixtureLocalNames(object: "message", value: "payload").wireJSON()
                == JSONValue.parse(#"{"object":"message","value":"payload"}"#))
    }

    @Test func booleanArrayValidatesEveryLiteral() throws {
        let valid = try JSONValue.parse(#"{"flags":[true,true]}"#)
        #expect(try FixtureBooleanArray(wireJSON: valid).wireJSON() == valid)
        #expect(throws: WireCodingError.self) {
            try FixtureBooleanArray(wireJSON: JSONValue.parse(#"{"flags":[true,false]}"#))
        }
    }

    @Test func booleanAdditionalValuesValidateOnDecodeAndEncode() throws {
        let valid = try JSONValue.parse(#"{"first":true,"second":true}"#)
        #expect(try FixtureBooleanMap(wireJSON: valid).wireJSON() == valid)
        #expect(throws: WireCodingError(.invalidDiscriminator)) {
            try FixtureBooleanMap(wireJSON: JSONValue.parse(#"{"first":false}"#))
        }
        #expect(throws: WireCodingError(.invalidDiscriminator)) {
            try FixtureBooleanMap(additionalFields: ["first": .boolean(false)]).wireJSON()
        }
    }

    @Test func booleanOneOfKeepsItsLiteralBranchesDisjoint() throws {
        let first = try FixtureBooleanUnion(wireJSON: .boolean(true))
        guard case .variant1 = first else {
            Issue.record("true must select the first literal branch")
            return
        }
        #expect(try first.wireJSON() == .boolean(true))
        let second = try FixtureBooleanUnion(wireJSON: .boolean(false))
        guard case .variant2 = second else {
            Issue.record("false must select the second literal branch")
            return
        }
        #expect(try second.wireJSON() == .boolean(false))
        #expect(throws: WireCodingError(.typeMismatch)) { try FixtureBooleanUnion(wireJSON: .null) }
    }

    @Test func unambiguousNullableOneOfKeepsRequirednessAndValidation() throws {
        for input in [#"{"value":null}"#, #"{"value":"yes"}"#] {
            let json = try JSONValue.parse(input)
            #expect(try FixtureNullableOne(wireJSON: json).wireJSON() == json)
        }
        #expect(try FixtureNullableOne(value: nil).wireJSON() == JSONValue.parse(#"{"value":null}"#))
        #expect(throws: WireCodingError(.missingField, path: ["value"])) {
            try FixtureNullableOne(wireJSON: .object([:]))
        }
        #expect(throws: WireCodingError(.invalidDiscriminator, path: ["value"])) {
            try FixtureNullableOne(wireJSON: JSONValue.parse(#"{"value":"no"}"#))
        }
    }
}
