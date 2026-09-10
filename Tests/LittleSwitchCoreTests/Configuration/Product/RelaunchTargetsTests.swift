import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Relaunch targets")
struct RelaunchTargetsTests {
    @Test("Nothing is scheduled by default")
    func emptyByDefault() {
        #expect(RelaunchTargets.none.isEmpty)
        #expect(!RelaunchTargets(codex: true).isEmpty)
    }

    @Test("Targets capture exactly the connected products")
    func capturesConnectedProducts() {
        let targets = RelaunchTargets(
            claude: true,
            codex: false,
            claudeCode: true,
            openCode: false
        )

        #expect(targets.claude)
        #expect(!targets.codex)
        #expect(targets.claudeCode)
        #expect(!targets.openCode)
    }

    @Test("A configuration written before this field still decodes")
    func decodesLegacyConfiguration() throws {
        let legacy = """
            {"version":7,"providers":[],"mappings":{},"autoMode":true,"connected":false}
            """

        let configuration = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(legacy.utf8)
        )

        #expect(configuration.relaunchTargets == .none)
    }

    @Test("Targets survive a round trip")
    func roundTrip() throws {
        var configuration = AppConfiguration()
        configuration.relaunchTargets = RelaunchTargets(codex: true, openCode: true)

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)

        #expect(decoded.relaunchTargets == configuration.relaunchTargets)
    }
}
