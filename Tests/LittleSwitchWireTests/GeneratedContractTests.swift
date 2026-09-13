import Foundation
import LittleSwitchWire
import LittleSwitchWireContractFixtures
import Testing

@Suite("Compiled generated wire contracts")
struct GeneratedContractTests {
    @Test func publicConstructionAndAllFourPresenceStates() throws {
        let base = FixturePresence(amount: try JSONNumber("1.25"), class: .public, nullable: nil, required: "ready")
        #expect(base.optional == nil)
        #expect(base.presence == .absent)
        #expect(
            try base.wireJSON()
                == JSONValue.parse(#"{"amount":1.25,"class":"public","nullable":null,"required":"ready"}"#))
        var value = base
        value.optional = "optional"
        value.presence = .null
        value.nullable = "present"
        let decoded = try WireCodec.decode(FixturePresence.self, from: WireCodec.encode(value)).value
        #expect(decoded.nullable == "present")
        #expect(decoded.optional == "optional")
        #expect(decoded.presence == .null)
        value.presence = .value("value")
        #expect(
            try WireCodec.decode(FixturePresence.self, from: WireCodec.encode(value)).value.presence == .value("value"))
    }

    @Test func missingNullableAndNullNonnullableFailAtField() {
        #expect(throws: WireCodingError(.missingField, path: ["nullable"])) {
            try FixturePresence(wireJSON: JSONValue.parse(#"{"amount":1,"class":"public","required":"a"}"#))
        }
        #expect(throws: WireCodingError(.unexpectedNull, path: ["optional"])) {
            try FixturePresence(
                wireJSON: JSONValue.parse(
                    #"{"amount":1,"class":"public","nullable":null,"optional":null,"required":"a"}"#))
        }
        #expect(throws: WireCodingError(.invalidDiscriminator, path: ["class"])) {
            try FixturePresence(
                wireJSON: JSONValue.parse(#"{"amount":1,"class":"future","nullable":null,"required":"a"}"#))
        }
    }

    @Test func exactNumbersAndExtrasSurviveAndCollisionsFail() throws {
        let json = try JSONValue.parse(
            #"{"amount":18446744073709551615,"class":"private","nullable":null,"required":"a","vendor":{"precise":1.234567890123456789e-88}}"#
        )
        var value = try FixturePresence(wireJSON: json)
        #expect(try value.wireJSON() == json)
        #expect(
            try WireCodec.decode(FixturePresence.self, from: WireCodec.encode(value)).value.amount
                == JSONNumber("18446744073709551615"))
        value.additionalFields["required"] = .string("collision")
        #expect(throws: WireCodingError(.additionalFieldCollision, path: ["required"])) { try value.wireJSON() }
    }

    @Test func taggedUnionPreservesKnownAndUnknownFullPayload() throws {
        let known = try JSONValue.parse(#"{"type":"text","text":"hello","vendor":18446744073709551615}"#)
        let value = try FixtureTagged(wireJSON: known)
        guard case .text(let text) = value else {
            Issue.record("Expected the text branch")
            return
        }
        #expect(text.text == "hello")
        #expect(try value.wireJSON() == known)
        let unknown = try JSONValue.parse(#"{"type":"future","opaque":[null,{"amount":1e400}]}"#)
        let future = try FixtureTagged(wireJSON: unknown)
        // swiftlint:disable:next pattern_matching_keywords
        guard case .unknown(let type, let payload) = future else {
            Issue.record("Expected opaque future branch")
            return
        }
        #expect(type == "future")
        #expect(payload == unknown)
        #expect(try future.wireJSON() == unknown)
        let tool = try FixtureTagged(wireJSON: JSONValue.parse(#"{"type":"tool","input":null}"#))
        #expect(try tool.wireJSON() == JSONValue.parse(#"{"type":"tool","input":null}"#))
    }

    @Test func malformedKnownTagNeverFallsBackToUnknown() {
        #expect(throws: WireCodingError(.missingField, path: ["text"])) {
            try FixtureTagged(wireJSON: JSONValue.parse(#"{"type":"text","vendor":true}"#))
        }
        #expect(throws: WireCodingError(.typeMismatch, path: ["text"])) {
            try FixtureTagged(wireJSON: JSONValue.parse(#"{"type":"text","text":false}"#))
        }
        for input in [#"{}"#, #"{"type":null}"#, #"{"type":42}"#] {
            #expect(throws: WireCodingError.self) { try FixtureTagged(wireJSON: JSONValue.parse(input)) }
        }
        #expect(throws: WireCodingError(.invalidDiscriminator)) {
            try FixtureTagged.unknown(type: "text", payload: JSONValue.parse(#"{"type":"text","text":"a"}"#)).wireJSON()
        }
        #expect(throws: WireCodingError(.invalidDiscriminator)) {
            try FixtureTagged.unknown(type: "other", payload: JSONValue.parse(#"{"type":"future"}"#)).wireJSON()
        }
    }

    @Test func anyOfChoosesFirstValidBranchAndOneOfRequiresExactlyOne() throws {
        let both = try JSONValue.parse(#"{"left":"first","right":1.25,"vendor":true}"#)
        let value = try FixtureAny(wireJSON: both)
        guard case .variant1 = value else {
            Issue.record("anyOf must prefer source order")
            return
        }
        #expect(try value.wireJSON() == both)
        #expect(throws: WireCodingError(.typeMismatch)) { try FixtureOne(wireJSON: both) }
        let ambiguous = FixtureOne.variant1(FixtureOneVariant1(left: "first", additionalFields: ["right": .integer(1)]))
        #expect(throws: WireCodingError(.typeMismatch)) { try ambiguous.wireJSON() }
        #expect(throws: WireCodingError(.typeMismatch)) { try FixtureAny(wireJSON: .object([:])) }
        for input in [#"{"left":"a"}"#, #"{"right":1.5}"#] {
            let json = try JSONValue.parse(input)
            #expect(try FixtureOne(wireJSON: json).wireJSON() == json)
        }
    }

    @Test func streamRequestUnionKeepsAbsentFalseTrueAndNullDistinct() throws {
        for input in [#"{"model":"m"}"#, #"{"model":"m","stream":false}"#, #"{"model":"m","stream":true}"#] {
            let json = try JSONValue.parse(input)
            #expect(try FixtureStream(wireJSON: json).wireJSON() == json)
            #expect(try FixtureNullableStream(wireJSON: json).wireJSON() == json)
        }
        let null = try JSONValue.parse(#"{"model":"m","stream":null}"#)
        #expect(throws: WireCodingError(.typeMismatch)) { try FixtureStream(wireJSON: null) }
        #expect(try FixtureNullableStream(wireJSON: null).wireJSON() == null)
        #expect(throws: WireCodingError(.invalidDiscriminator, path: ["stream"])) {
            try FixtureStreamVariant1(wireJSON: JSONValue.parse(#"{"model":"m","stream":true}"#))
        }
        #expect(throws: WireCodingError(.invalidDiscriminator, path: ["stream"])) {
            try FixtureNullableStreamVariant1(wireJSON: JSONValue.parse(#"{"model":"m","stream":true}"#))
        }
        #expect(
            try FixtureStreamVariant1(model: "m", stream: .value).wireJSON()
                == JSONValue.parse(#"{"model":"m","stream":false}"#))
        #expect(
            try FixtureNullableStreamVariant1(model: "m", stream: .value(.value)).wireJSON()
                == JSONValue.parse(#"{"model":"m","stream":false}"#))
    }

    @Test func nullableArraysTypedExtrasAndClosedObjectsAreValidated() throws {
        let array = try JSONValue.parse(#"{"values":[1.5,null,18446744073709551615]}"#)
        #expect(try FixtureNested(wireJSON: array).wireJSON() == array)
        #expect(throws: WireCodingError(.typeMismatch)) {
            try FixtureNested(wireJSON: JSONValue.parse(#"{"values":[],"extra":true}"#))
        }
        #expect(throws: WireCodingError(.typeMismatch)) {
            try FixtureNested(values: [], additionalFields: ["extra": .boolean(true)]).wireJSON()
        }
        let map = try JSONValue.parse(#"{"amount":1.25,"none":null}"#)
        #expect(try FixtureMap(wireJSON: map).wireJSON() == map)
        #expect(throws: WireCodingError(.typeMismatch)) {
            try FixtureMap(wireJSON: JSONValue.parse(#"{"amount":"wrong"}"#))
        }
        #expect(throws: WireCodingError(.typeMismatch)) {
            try FixtureMap(additionalFields: ["bad": .string("wrong")]).wireJSON()
        }
    }

    @Test func scalarUnionAndExplicitProjectionPreserveValues() throws {
        for input in [#""text""#, "1e400", "false"] {
            let json = try JSONValue.parse(input)
            #expect(try FixtureScalar(wireJSON: json).wireJSON() == json)
        }
        #expect(throws: WireCodingError(.typeMismatch)) { try FixtureScalar(wireJSON: .null) }
        let source = try JSONValue.parse(#"{"type":"projected","kept":"yes","other":1.25,"vendor":true}"#)
        let projected = try FixtureProjection(wireJSON: source)
        #expect(projected.kept == "yes")
        #expect(FixtureProjection.Key.kept.rawValue == "kept")
        #expect(FixtureProjection.Key.allCases == [.kept, .type])
        #expect(try projected.wireJSON() == source)
        #expect(throws: WireCodingError(.missingField, path: ["type"])) {
            try FixtureProjection(wireJSON: JSONValue.parse(#"{"kept":"yes"}"#))
        }
    }

    @Test func indirectRecursiveUnionCompilesAndRoundTrips() throws {
        let json = try JSONValue.parse(#"{"type":"branch","child":{"type":"leaf","value":"yes"}}"#)
        #expect(try FixtureRecursive(wireJSON: json).wireJSON() == json)
    }
}
