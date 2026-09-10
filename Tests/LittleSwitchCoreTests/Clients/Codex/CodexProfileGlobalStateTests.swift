import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile desktop state")
struct CodexProfileGlobalStateTests {
    @Test("Activation enables Max in the desktop effort menu without touching other state")
    func desktopEffortMenu() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let globalState = fixture.paths.config
            .deletingLastPathComponent()
            .appending(path: ".codex-global-state.json")

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        let created = try Data(contentsOf: globalState)
        let createdRoot = try #require(
            JSONSerialization.jsonObject(with: created) as? [String: Any]
        )
        let createdAtoms = try #require(
            createdRoot[CodexGlobalState.persistedAtomStateKey] as? [String: Any]
        )
        #expect(
            try #require(createdAtoms[CodexGlobalState.enabledReasoningEffortsKey] as? [String])
                == CodexGlobalState.reasoningEffortsIncludingMaximum
        )

        try Data(
            #"{"electron-persisted-atom-state":{"enabled-reasoning-efforts":["low"],"other":true}}"#
                .utf8
        )
        .write(to: globalState)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )

        let merged = try Data(contentsOf: globalState)
        let mergedRoot = try #require(
            JSONSerialization.jsonObject(with: merged) as? [String: Any]
        )
        let mergedAtoms = try #require(
            mergedRoot[CodexGlobalState.persistedAtomStateKey] as? [String: Any]
        )
        #expect(
            try #require(mergedAtoms[CodexGlobalState.enabledReasoningEffortsKey] as? [String])
                == ["low", "max"]
        )
        #expect(mergedAtoms["other"] as? Bool == true)
    }
}
