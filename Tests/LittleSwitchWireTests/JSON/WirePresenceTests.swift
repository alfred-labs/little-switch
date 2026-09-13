import Foundation
import LittleSwitchWire
import Testing

@Suite("Wire field presence")
struct WirePresenceTests {
    @Test func explicitValueProjectionCollapsesOnlyAbsentAndNull() {
        #expect(JSONPresence<String>.absent.value == nil)
        #expect(JSONPresence<String>.null.value == nil)
        #expect(JSONPresence.value("kept").value == "kept")
    }

    @Test func nullableRequiredFieldStillRequiresItsKey() throws {
        let object = try WireObject(JSONValue.parse(#"{"nullable":null}"#))
        let nullable: String? = try object.nullable("nullable")
        #expect(nullable == nil)
        #expect(throws: WireCodingError(.missingField, path: ["missing"])) {
            let _: String? = try object.nullable("missing")
        }
    }

    @Test func optionalNonNullableRejectsExplicitNull() throws {
        let object = try WireObject(JSONValue.parse(#"{"value":null}"#))
        let absent: String? = try object.optional("missing")
        #expect(absent == nil)
        #expect(throws: WireCodingError(.unexpectedNull, path: ["value"])) {
            let _: String? = try object.optional("value")
        }
    }

    @Test func preservesAllThreeOptionalNullableStates() throws {
        let object = try WireObject(JSONValue.parse(#"{"null":null,"value":"text"}"#))
        let absent: JSONPresence<String> = try object.presence("missing")
        let null: JSONPresence<String> = try object.presence("null")
        let value: JSONPresence<String> = try object.presence("value")
        #expect(absent == .absent)
        #expect(null == .null)
        #expect(value == .value("text"))
        var output = try WireObject(additionalFields: [:], knownKeys: ["missing", "null", "value"])
        try output.setPresence(absent, for: "missing")
        try output.setPresence(null, for: "null")
        try output.setPresence(value, for: "value")
        #expect(output.wireJSON == object.wireJSON)
    }

    @Test func requiredFieldsRejectMissingNullAndWrongShape() throws {
        let object = try WireObject(JSONValue.parse(#"{"null":null,"bad":false,"good":"value"}"#))
        let good: String = try object.required("good")
        #expect(good == "value")
        for (key, kind) in [
            ("missing", WireCodingError.Kind.missingField), ("null", .unexpectedNull), ("bad", .typeMismatch),
        ] {
            #expect(throws: WireCodingError(kind, path: [key])) {
                let _: String = try object.required(key)
            }
        }
        #expect(throws: WireCodingError(.typeMismatch)) { try WireObject(.array([])) }
    }

    @Test func extrasCannotOverrideKnownFieldsAndRetainNumbers() throws {
        let object = try WireObject(JSONValue.parse(#"{"role":"assistant","extra":18446744073709551615}"#))
        let extras = object.additionalFields(excluding: ["role"])
        var output = try WireObject(additionalFields: extras, knownKeys: ["role"])
        try output.set("user", for: "role")
        #expect(output.wireJSON == (try JSONValue.parse(#"{"role":"user","extra":18446744073709551615}"#)))
        #expect(throws: WireCodingError(.additionalFieldCollision, path: ["role"])) {
            try WireObject(additionalFields: ["role": .string("injected")], knownKeys: ["role"])
        }
    }

    @Test func outputNullAndAbsenceAreContextual() throws {
        var object = try WireObject(additionalFields: [:], knownKeys: ["optional", "nullable"])
        try object.setOptional(String?.none, for: "optional")
        try object.setNullable(String?.none, for: "nullable")
        #expect(object.wireJSON == (try JSONValue.parse(#"{"nullable":null}"#)))
        try object.setOptional("a", for: "optional")
        try object.setNullable("b", for: "nullable")
        #expect(object.wireJSON == (try JSONValue.parse(#"{"optional":"a","nullable":"b"}"#)))
    }
}
