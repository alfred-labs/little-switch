import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code configuration")
struct ClaudeCodeConfigurationTests {
    @Test("Context mode round-trips through Codable")
    func contextModeRoundTrip() throws {
        let configuration = ClaudeCodeConfiguration(
            connected: true,
            defaultModel: "claude-opus-5",
            contextMode: .extended1M
        )

        let encoded = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(ClaudeCodeConfiguration.self, from: encoded) == configuration)
    }

    @Test("Legacy settings decode with standard context")
    func legacyContextMode() throws {
        let decoded = try JSONDecoder().decode(
            ClaudeCodeConfiguration.self,
            from: Data(
                #"{"connected":true,"defaultModel":"claude-opus-5"}"#.utf8
            )
        )

        #expect(
            decoded
                == ClaudeCodeConfiguration(
                    connected: true,
                    defaultModel: "claude-opus-5",
                    contextMode: .standard
                )
        )
    }

    @Test("Normalization keeps 1M only for an eligible mapped model")
    func contextEligibility() {
        let fixture = fixture()
        var provider = fixture.provider
        provider.models[0].contextWindowOverride = 1_000_000

        let eligible = ClaudeCodeConfiguration(
            defaultModel: "claude-opus-5",
            contextMode: .extended1M
        )
        #expect(
            eligible.normalized(
                providers: [provider],
                mappings: fixture.mappings
            ) == eligible
        )

        let ineligible = ClaudeCodeConfiguration(
            defaultModel: "claude-sonnet-5",
            contextMode: .extended1M
        )
        #expect(
            ineligible.normalized(
                providers: [provider],
                mappings: fixture.mappings
            ).contextMode == .standard
        )
    }

    @Test("Normalization retains a valid default")
    func retainsDefault() {
        let fixture = fixture()
        let configuration = ClaudeCodeConfiguration(
            connected: true,
            defaultModel: "claude-opus-5"
        )

        #expect(
            configuration.normalized(
                providers: [fixture.provider],
                mappings: fixture.mappings
            ) == configuration
        )
    }

    @Test("Normalization prefers the mapped default Sonnet route")
    func sonnetFallback() {
        let fixture = fixture()

        #expect(
            ClaudeCodeConfiguration(connected: true, defaultModel: "missing")
                .normalized(
                    providers: [fixture.provider],
                    mappings: fixture.mappings
                )
                == ClaudeCodeConfiguration(
                    connected: true,
                    defaultModel: "claude-sonnet-5"
                )
        )
    }

    @Test("Normalization falls back in stable route order without Sonnet")
    func stableFallback() throws {
        let fixture = fixture()
        let mappings = [
            "claude-opus-5": try #require(fixture.mappings["claude-opus-5"]),
            "claude-haiku-4-5-20251001": try #require(
                fixture.mappings["claude-haiku-4-5-20251001"]
            ),
        ]

        #expect(
            ClaudeCodeConfiguration(defaultModel: "missing")
                .normalized(providers: [fixture.provider], mappings: mappings)
                .defaultModel == "claude-opus-5"
        )
    }

    @Test("Only discovered provider model mappings are available")
    func validatesMappings() {
        let fixture = fixture()
        let missingProvider = UUID()
        let mappings = fixture.mappings.merging([
            "claude-fable-5": ModelMapping(
                providerID: fixture.provider.id,
                modelID: "missing"
            ),
            "claude-haiku-4-5-20251001": ModelMapping(
                providerID: missingProvider,
                modelID: "glm"
            ),
        ]) { _, replacement in replacement }

        #expect(
            ClaudeCodeConfiguration().mappedRouteIDs(
                providers: [fixture.provider],
                mappings: mappings
            ) == ["claude-opus-5", "claude-sonnet-5"]
        )
    }

    @Test("Empty routing clears a stale default without changing connection intent")
    func emptyRouting() {
        #expect(
            ClaudeCodeConfiguration(connected: true, defaultModel: "missing")
                .normalized(providers: [], mappings: [:])
                == ClaudeCodeConfiguration(connected: true, defaultModel: nil)
        )
        #expect(ClaudeCodeConfiguration.disconnected == ClaudeCodeConfiguration())
    }

    private func fixture() -> (provider: Provider, mappings: [String: ModelMapping]) {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [
                DiscoveredModel(id: "glm"),
                DiscoveredModel(id: "qwen"),
                DiscoveredModel(id: "haiku"),
            ]
        )
        return (
            provider,
            [
                "claude-opus-5": ModelMapping(
                    providerID: providerID,
                    modelID: "glm"
                ),
                "claude-sonnet-5": ModelMapping(
                    providerID: providerID,
                    modelID: "qwen"
                ),
                "claude-haiku-4-5-20251001": ModelMapping(
                    providerID: providerID,
                    modelID: "haiku"
                ),
            ]
        )
    }
}
