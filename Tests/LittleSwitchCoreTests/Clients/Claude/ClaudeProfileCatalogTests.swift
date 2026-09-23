import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Claude profile catalog publication")
struct ClaudeProfileCatalogTests {
    @Test("Explicit choices publish capacity, membership and indicator changes", arguments: CatalogChange.allCases)
    func publishesChoices(change: CatalogChange) throws {
        let fixture = try ClaudeCatalogProfileFixture()
        defer { fixture.remove() }
        let before = try fixture.profile.snapshots()
        let choices = try changedChoices(change)
        #expect(try !fixture.manager.catalogMatches(choices))

        try fixture.manager.updateCatalog(choices, autoMode: false)

        #expect(try fixture.manager.catalogMatches(choices))
        let profile = try fixture.profile.object(at: fixture.profile.paths.profile)
        #expect(try jsonData(profile["inferenceModels"]) == jsonData(expectedModels(change)))
        #expect(profile["modelDiscoveryEnabled"] as? Bool == true)
        try fixture.assertOnlyCatalogChanged(from: before)
        #expect(fixture.store.writes == [fixture.profile.paths.profile])
        #expect(fixture.store.restores.isEmpty)
        if case .capacity = change {
            try fixture.manager.updateCatalog([choice()], autoMode: false)
            let reduced = try fixture.profile.object(at: fixture.profile.paths.profile)
            #expect(try jsonData(reduced["inferenceModels"]) == jsonData([ClaudeCatalogProfileFixture.sonnet]))
        }
    }

    @Test("Matching catalog payloads do not rewrite any file")
    func matchingCatalogDoesNotWrite() throws {
        let fixture = try ClaudeCatalogProfileFixture()
        defer { fixture.remove() }
        let before = try fixture.profile.snapshots()
        let choices = try [choice()]
        #expect(try fixture.manager.catalogMatches(choices))

        try fixture.manager.updateCatalog(choices, autoMode: false)

        #expect(fixture.store.writes.isEmpty)
        #expect(fixture.store.restores.isEmpty)
        #expect(try fixture.profile.snapshots() == before)
    }

    @Test("Empty choices remove an existing model list", arguments: [false, true])
    func emptyCatalogRemovesModels(alreadyEmptyArray: Bool) throws {
        let fixture = try ClaudeCatalogProfileFixture()
        defer { fixture.remove() }
        if alreadyEmptyArray {
            var profile = try fixture.profile.object(at: fixture.profile.paths.profile)
            profile["inferenceModels"] = [Any]()
            try fixture.profile.writeJSON(profile, to: fixture.profile.paths.profile)
        }
        let before = try fixture.profile.snapshots()
        #expect(try !fixture.manager.catalogMatches([]))

        try fixture.manager.updateCatalog([], autoMode: false)
        try fixture.manager.updateCatalog([], autoMode: false)

        #expect(try fixture.manager.catalogMatches([]))
        #expect(try fixture.profile.object(at: fixture.profile.paths.profile)["inferenceModels"] == nil)
        #expect(fixture.store.writes == [fixture.profile.paths.profile])
        try fixture.assertOnlyCatalogChanged(from: before)
    }

    @Test("Missing and malformed catalog settings can be repaired", arguments: CatalogDamage.allCases)
    func repairsCatalog(damage: CatalogDamage) throws {
        let fixture = try ClaudeCatalogProfileFixture()
        defer { fixture.remove() }
        var profile = try fixture.profile.object(at: fixture.profile.paths.profile)
        switch damage {
        case .missingDiscovery:
            profile.removeValue(forKey: "modelDiscoveryEnabled")
        case .disabledDiscovery:
            profile["modelDiscoveryEnabled"] = false
        case .missingModels:
            profile.removeValue(forKey: "inferenceModels")
        case .malformedModels:
            profile["inferenceModels"] = "not a model list"
        case .foreignModels:
            profile["inferenceModels"] = [["name": "foreign-model"]]
        }
        try fixture.profile.writeJSON(profile, to: fixture.profile.paths.profile)
        let before = try fixture.profile.snapshots()
        let choices = try [choice()]
        #expect(try !fixture.manager.catalogMatches(choices))

        try fixture.manager.updateCatalog(choices, autoMode: false)

        #expect(try fixture.manager.catalogMatches(choices))
        let updated = try fixture.profile.object(at: fixture.profile.paths.profile)
        #expect(try jsonData(updated["inferenceModels"]) == jsonData([ClaudeCatalogProfileFixture.sonnet]))
        try fixture.assertOnlyCatalogChanged(from: before)
    }

    @Test("A matching catalog does not authorize updating a foreign profile")
    func rejectsForeignOwnership() throws {
        let fixture = try ClaudeCatalogProfileFixture()
        defer { fixture.remove() }
        var profile = try fixture.profile.object(at: fixture.profile.paths.profile)
        profile["inferenceGatewayBaseUrl"] = "https://foreign.example.com"
        try fixture.profile.writeJSON(profile, to: fixture.profile.paths.profile)
        let before = try fixture.profile.snapshots()
        let choices = try [choice()]
        #expect(try fixture.manager.catalogMatches(choices))

        #expect(throws: ClaudeProfileManager.Error.inactiveProfile) {
            try fixture.manager.updateCatalog(choices, autoMode: false)
        }

        #expect(fixture.store.writes.isEmpty)
        #expect(fixture.store.restores.isEmpty)
        #expect(try fixture.profile.snapshots() == before)
    }

    @Test("Failed writes restore the exact profile snapshot", arguments: CatalogProfileFileStore.Failure.writeFailures)
    func failedWriteRestoresSnapshot(failure: CatalogProfileFileStore.Failure) throws {
        let fixture = try ClaudeCatalogProfileFixture(failure: failure)
        defer { fixture.remove() }
        let before = try fixture.profile.snapshots()
        let choices = try changedChoices(.capacity)

        #expect(throws: CatalogProfileFileStore.Error.write) {
            try fixture.manager.updateCatalog(choices, autoMode: false)
        }

        #expect(try fixture.profile.snapshots() == before)
        #expect(fixture.store.restores == [fixture.profile.paths.profile])
    }

    @Test("A failed compensation reports rollback failure")
    func rollbackFailureIsExplicit() throws {
        let fixture = try ClaudeCatalogProfileFixture(failure: .partialWriteAndRestore)
        defer { fixture.remove() }
        let before = try fixture.profile.snapshots()
        let choices = try changedChoices(.capacity)

        #expect(throws: ClaudeProfileManager.Error.rollbackFailed) {
            try fixture.manager.updateCatalog(choices, autoMode: false)
        }

        #expect(fixture.store.restores == [fixture.profile.paths.profile])
        #expect(try fixture.manager.catalogMatches(choices))
        try fixture.assertOnlyCatalogChanged(from: before)
    }

    private func choice(
        family: String = "sonnet", supports1M: Bool = false, indicator: ModelIndicator = .mapsTo
    ) throws -> ClaudeCodeModelChoice {
        let route = try #require(ClaudeRoute.all.first { $0.family == family })
        return ClaudeCodeModelChoice(route: route, supports1MContext: supports1M, indicator: indicator)
    }

    private func changedChoices(_ change: CatalogChange) throws -> [ClaudeCodeModelChoice] {
        switch change {
        case .capacity: try [choice(supports1M: true)]
        case .membership: try [choice(family: "opus"), choice()]
        case .indicator: try [choice(indicator: .swap)]
        }
    }

    private func expectedModels(_ change: CatalogChange) -> [[String: Any]] {
        var sonnet = ClaudeCatalogProfileFixture.sonnet
        switch change {
        case .capacity:
            sonnet["supports1m"] = true
        case .membership:
            return [
                [
                    "name": "claude-opus-5", "labelOverride": "Opus 5 ↦", "anthropicFamilyTier": "opus",
                    "isFamilyDefault": true, "maxEffort": "max",
                ],
                sonnet,
            ]
        case .indicator:
            sonnet["labelOverride"] = "Sonnet 5 ⇄"
        }
        return [sonnet]
    }

    private func jsonData(_ object: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: #require(object), options: [.sortedKeys, .fragmentsAllowed])
    }
}

extension ClaudeProfileCatalogTests {
    enum CatalogChange: CaseIterable, Sendable {
        case capacity, membership, indicator
    }

    enum CatalogDamage: CaseIterable, Sendable {
        case missingDiscovery, disabledDiscovery, missingModels, malformedModels, foreignModels
    }
}
