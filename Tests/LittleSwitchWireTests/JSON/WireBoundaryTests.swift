import Foundation
import LittleSwitchWire
import Testing

@Suite("Wire boundary qualification")
struct WireBoundaryTests {
    @Test func nestedArraysRetainTheFullFailurePath() throws {
        let object = try WireObject(JSONValue.parse(#"{"items":[["valid"],[false]]}"#))
        #expect(throws: WireCodingError(.typeMismatch, path: ["items", "1", "0"])) {
            let _: [[String]] = try object.required("items")
        }
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode([String].self, from: Data("{}".utf8))
        }
    }

    @Test func numberValuesRetainLongDecimalsWithoutDouble() throws {
        let data = Data("0.123456789012345678901234567890123456789".utf8)
        let value = try WireCodec.decode(JSONNumber.self, from: data).value
        #expect(try WireCodec.encode(value) == data)
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode(JSONNumber.self, from: Data(#""1""#.utf8))
        }
    }

    @Test func duplicateKeysKeepOriginalBytesAndExposeLastValue() throws {
        let data = Data(#"{"value":1,"value":2}"#.utf8)
        let document = try WireCodec.decode(JSONValue.self, from: data)
        #expect(document.originalData == data)
        #expect(document.value.object?["value"] == .integer(2))
    }

    @Test func parserResourceLimitFailsAsAValueFreeError() {
        let data = Data((String(repeating: "[", count: 300) + "0" + String(repeating: "]", count: 300)).utf8)
        #expect(throws: WireCodingError(.invalidJSON)) {
            try WireCodec.decode(JSONValue.self, from: data)
        }
    }

    @Test func absentMutationRemovesAnExistingValue() throws {
        var object = try WireObject(JSONValue.parse(#"{"value":"previous"}"#))
        try object.setPresence(JSONPresence<String>.absent, for: "value")
        #expect(object.wireJSON == .object([:]))
    }

    @Test func nullableValueAndNestedFailuresArePreserved() throws {
        let object = try WireObject(JSONValue.parse(#"{"good":"text","bad":false}"#))
        let value: String? = try object.nullable("good")
        #expect(value == "text")
        #expect(throws: WireCodingError(.typeMismatch, path: ["bad"])) {
            let _: String? = try object.nullable("bad")
        }
        #expect(throws: WireCodingError(.typeMismatch, path: ["bad"])) {
            let _: JSONPresence<String> = try object.presence("bad")
        }
    }

    @Test func unclassifiedErrorsNeverEscapeTheDataBoundary() {
        #expect(throws: WireCodingError(.typeMismatch)) {
            try WireCodec.decode(UnclassifiedFailure.self, from: Data("{}".utf8))
        }
        #expect(throws: WireCodingError(.invalidJSON)) {
            try WireCodec.encode(UnclassifiedFailure())
        }
        #expect(throws: WireCodingError(.invalidDiscriminator, path: ["type"])) {
            try WireCodec.encode(ClassifiedFailure())
        }
    }
}

private struct UnclassifiedFailure: WireCodable {
    enum Failure: Error { case privateValue(String) }
    init() {}
    init(wireJSON: JSONValue) throws { throw Failure.privateValue("private input") }
    func wireJSON() throws -> JSONValue { throw Failure.privateValue("private output") }
}

private struct ClassifiedFailure: WireCodable {
    init() {}
    init(wireJSON: JSONValue) {}
    func wireJSON() throws -> JSONValue {
        throw WireCodingError(.invalidDiscriminator, path: ["type"])
    }
}
