import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Exact JSON across legacy domain transformations")
struct WireJSONCompatibilityTests {
    @Test("Opaque number lexemes survive nested dictionary edits")
    func exactNumbersAndGenuineBooleans() throws {
        let data = Data(#"{"values":[1e400,1e-400,18446744073709551617,true,null,"Δ"]}"#.utf8)
        var fields = try WireJSONCompatibility.fields(data)
        let values = try #require(fields["values"] as? [Any])
        #expect(values[3] as? Bool == true)
        #expect(values[0] as? NSNumber == nil)
        fields["selected"] = false
        fields["count"] = 42
        let encoded = try WireJSONCompatibility.data(fields)
        #expect(
            encoded
                == Data(
                    #"{"count":42,"selected":false,"values":[1e400,1e-400,18446744073709551617,true,null,"Δ"]}"#.utf8))
    }

    @Test("Invalid legacy leaves fail without invoking Objective-C JSON serialization")
    func rejectsInvalidLeaves() throws {
        let invalidValues: [Any] = [Date(timeIntervalSince1970: 0), Double.nan, Double.infinity]
        for value in invalidValues {
            #expect(throws: (any Error).self) {
                try WireJSONCompatibility.data(["opaque": [value]])
            }
        }
        #expect(throws: WireJSONCompatibility.Error.self) {
            try WireJSONCompatibility.fields(Data("[]".utf8))
        }
    }
}
