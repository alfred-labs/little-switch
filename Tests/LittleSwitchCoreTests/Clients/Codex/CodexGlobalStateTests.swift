import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex global state")
struct CodexGlobalStateTests {
    @Test("A missing document is created with the default efforts including Max")
    func createsMissingDocument() throws {
        let data = try #require(try CodexGlobalState.enablingMaximumReasoningEffort(in: nil))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let atoms = try #require(root[CodexGlobalState.persistedAtomStateKey] as? [String: Any])
        let efforts = try #require(atoms[CodexGlobalState.enabledReasoningEffortsKey] as? [String])
        #expect(efforts == CodexGlobalState.reasoningEffortsIncludingMaximum)
    }

    @Test("Existing effort lists gain Max and preserve order and other atoms")
    func mergesExistingLists() throws {
        let original = """
            {"other-section":1,"electron-persisted-atom-state":{"composer-atom":false,\
            "enabled-reasoning-efforts":["low","high"]}}
            """
        let updated = try #require(
            try CodexGlobalState.enablingMaximumReasoningEffort(in: Data(original.utf8))
        )
        let root = try #require(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let atoms = try #require(root[CodexGlobalState.persistedAtomStateKey] as? [String: Any])
        #expect(
            try #require(atoms[CodexGlobalState.enabledReasoningEffortsKey] as? [String])
                == ["low", "high", "max"]
        )
        #expect(atoms["composer-atom"] as? Bool == false)
        #expect(root["other-section"] != nil)
    }

    @Test("An absent effort key adopts the default list next to existing atoms")
    func adoptsDefaultList() throws {
        let original = #"{"electron-persisted-atom-state":{"composer-atom":true}}"#
        let updated = try #require(
            try CodexGlobalState.enablingMaximumReasoningEffort(in: Data(original.utf8))
        )
        let root = try #require(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let atoms = try #require(root[CodexGlobalState.persistedAtomStateKey] as? [String: Any])
        #expect(
            try #require(atoms[CodexGlobalState.enabledReasoningEffortsKey] as? [String])
                == CodexGlobalState.reasoningEffortsIncludingMaximum
        )
        #expect(atoms["composer-atom"] as? Bool == true)
    }

    @Test("Documents without the atom section adopt the default list")
    func adoptsMissingSection() throws {
        let original = #"{"unrelated-section":true}"#
        let updated = try #require(
            try CodexGlobalState.enablingMaximumReasoningEffort(in: Data(original.utf8))
        )
        let root = try #require(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let atoms = try #require(root[CodexGlobalState.persistedAtomStateKey] as? [String: Any])
        let efforts = try #require(atoms[CodexGlobalState.enabledReasoningEffortsKey] as? [String])
        #expect(efforts == CodexGlobalState.reasoningEffortsIncludingMaximum)
        #expect(root["unrelated-section"] as? Bool == true)
    }

    @Test("Documents already enabling Max are left untouched")
    func skipsWhenMaxPresent() throws {
        let original = #"{"electron-persisted-atom-state":{"enabled-reasoning-efforts":["low","max"]}}"#
        #expect(try CodexGlobalState.enablingMaximumReasoningEffort(in: Data(original.utf8)) == nil)
    }

    @Test("Unrecognized documents are left untouched")
    func skipsForeignDocuments() throws {
        #expect(try CodexGlobalState.enablingMaximumReasoningEffort(in: Data("[1,2]".utf8)) == nil)
        #expect(try CodexGlobalState.enablingMaximumReasoningEffort(in: Data("not-json".utf8)) == nil)
        let nonDictionarySection =
            #"{"electron-persisted-atom-state":"unexpected"}"#
        #expect(
            try CodexGlobalState.enablingMaximumReasoningEffort(in: Data(nonDictionarySection.utf8))
                == nil
        )
        let invalidEfforts =
            #"{"electron-persisted-atom-state":{"enabled-reasoning-efforts":"low"}}"#
        #expect(
            try CodexGlobalState.enablingMaximumReasoningEffort(in: Data(invalidEfforts.utf8)) == nil
        )
    }
}
