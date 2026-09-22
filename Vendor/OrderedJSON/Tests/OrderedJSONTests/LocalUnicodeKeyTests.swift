import Foundation
import Testing

@testable import OrderedJSON

@Suite("Exact Unicode object key identity")
struct LocalUnicodeKeyTests {
  @Test func canonicalEquivalentsRemainDistinct() throws {
    let value = try JSONValue.parse(#"{"\u00e9":1,"e\u0301":2}"#)
    let fields = try #require(value.object)
    #expect(fields.count == 2)
    #expect(fields["\u{e9}"] == 1)
    #expect(fields["e\u{301}"] == 2)
    #expect(try JSONValue.parse(value.serialized()).object?.count == 2)
  }

  @Test func keyIdentityAffectsEqualityAndHashing() throws {
    let composed = try JSONValue.parse(#"{"\u00e9":1}"#)
    let decomposed = try JSONValue.parse(#"{"e\u0301":1}"#)
    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
  }

  @Test func trueDuplicatesKeepLastOccurrence() throws {
    let value = try JSONValue.parse(#"{"\u00e9":1,"e\u0301":2,"é":3}"#)
    let fields = try #require(value.object)
    #expect(fields.count == 2)
    #expect(fields["\u{e9}"] == 3)
    #expect(fields["e\u{301}"] == 2)
    #expect(Array(fields.keys).map { Array($0.utf8) } == [Array("e\u{301}".utf8), Array("\u{e9}".utf8)])
  }

  @Test func exactCollectionOperationsPreserveOrderAndIdentity() throws {
    var fields: JSONObject = ["é": 1, "e\u{301}": 2, "K": 3, "\u{212a}": 4]
    #expect(fields.count == 4)
    #expect(fields[fields.startIndex].value == 1)
    #expect(fields[fields.index(before: fields.endIndex)].value == 4)
    #expect(fields.index(after: fields.startIndex) == 1)
    #expect(fields.values == [1, 2, 3, 4])
    let transformed = fields.filter { $0.value != 3 }.mapValues { _ in .boolean(true) }
    #expect(transformed == ["é": true, "e\u{301}": true, "\u{212a}": true])
    #expect(fields.removeValue(forKey: "é") == 1)
    #expect(fields["e\u{301}"] == 2)
    fields["\u{212a}"] = nil
    #expect(fields == ["K": 3, "e\u{301}": 2])
    #expect(Set([fields, ["K": 3, "e\u{301}": 2]]).count == 1)
    #expect(fields != ["K": 3])
  }
}
